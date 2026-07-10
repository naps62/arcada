defmodule Arcada.RateLimit do
  @moduledoc """
  Per-caller rate limiting (issue #32), ETS-backed via `Hammer` — no Redis, no
  extra infra. Started in the supervision tree; entries self-expire.

  The one enforced path today is **semantic search** (`search_semantic/2`): the
  query-embedding leg hits the GPU/embeddings server, so we cap how often a
  single caller can spend it. Cheap Postgres FTS is never limited — when a caller
  is over budget, search *degrades to FTS-only* rather than failing (see
  `ArcadaWeb.RegisterLive`). The limit is therefore a load valve and a gentle
  signup nudge, not a hard wall.

  Two tiers, two windows each (per-minute smooths bursts, per-day is the real
  anti-abuse ceiling):

    * `:anon`  — keyed by an opaque per-visitor session id. Deliberately loose;
      until real client IP is available (RemoteIp, issue #43) a determined bot
      can reset its bucket by dropping the cookie, so this steers humans, not
      scripts. Global embedding serialization (the `Search.Index` GenServer) is
      the actual GPU backstop.
    * `:user`  — keyed by the verified account id. Much higher, since a real
      account is the retention outcome we want to reward.

  Limits are config-driven (`config :arcada, Arcada.RateLimit, ...`) so
  they can be tuned without a code change.
  """

  use Hammer, backend: :ets

  @type tier :: :anon | :user
  @type identity :: {tier(), term()}

  @minute :timer.minutes(1)
  @hour :timer.hours(1)
  @day :timer.hours(24)

  @defaults [
    anon: [per_minute: 20, per_day: 200],
    user: [per_minute: 120, per_day: 2_000]
  ]

  # Account emails (password reset + confirmation resend, issue #61). Two
  # dimensions: the *caller* (visitor id — a soft valve against a loop) and the
  # *target inbox* (the real anti-bombing / Resend-quota ceiling, since bombing a
  # victim must reuse their address regardless of cookie resets).
  @email_defaults [
    visitor: [per_minute: 5, per_day: 50],
    email: [per_hour: 3, per_day: 6]
  ]

  @doc """
  Charge one semantic search against `identity`'s budget.

  Returns `:ok` when allowed, or `{:deny, retry_after_ms}` for the window the
  caller has exhausted (the *shorter* wait of the two windows). Both the minute
  and day windows are charged on an allow so neither can be starved by the other;
  on the first denial we don't spend the remaining window.
  """
  @spec search_semantic(identity(), keyword()) :: :ok | {:deny, non_neg_integer()}
  def search_semantic({tier, _} = identity, opts \\ []) when tier in [:anon, :user] do
    limits = limits_for(tier, opts)

    with {:allow, _} <- hit({:search_min, identity}, @minute, limits[:per_minute]),
         {:allow, _} <- hit({:search_day, identity}, @day, limits[:per_day]) do
      :ok
    else
      {:deny, retry_ms} -> {:deny, retry_ms}
    end
  end

  @doc """
  Charge one account-email send (reset / confirmation resend) against both the
  caller (`visitor_key`) and the `email` inbox. Returns `:ok` when allowed, or
  `{:deny, retry_after_ms}` for the first exhausted window. Caller windows are
  charged before the inbox windows, so a looping caller is stopped without
  spending the victim's budget; a victim already at their cap is protected no
  matter who triggers it. Email is normalized (trim + downcase) so case/space
  variants share a bucket.

  Limits: `config :arcada, Arcada.RateLimit, email: [visitor: [...], email: [...]]`
  over `#{inspect(@email_defaults)}`.
  """
  @spec email_send(term(), String.t(), keyword()) :: :ok | {:deny, non_neg_integer()}
  def email_send(visitor_key, email, opts \\ []) do
    v = email_limits(:visitor, opts)
    e = email_limits(:email, opts)
    to = normalize_email(email)

    with {:allow, _} <- hit({:email_v_min, visitor_key}, @minute, v[:per_minute]),
         {:allow, _} <- hit({:email_v_day, visitor_key}, @day, v[:per_day]),
         {:allow, _} <- hit({:email_to_hour, to}, @hour, e[:per_hour]),
         {:allow, _} <- hit({:email_to_day, to}, @day, e[:per_day]) do
      :ok
    else
      {:deny, retry_ms} -> {:deny, retry_ms}
    end
  end

  defp email_limits(dimension, opts) do
    configured = Application.get_env(:arcada, __MODULE__, [])
    email_cfg = Keyword.get(configured, :email, [])

    @email_defaults
    |> Keyword.fetch!(dimension)
    |> Keyword.merge(Keyword.get(email_cfg, dimension, []))
    |> Keyword.merge(Keyword.get(opts, dimension, []))
  end

  defp normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  defp normalize_email(other), do: other

  @doc "The configured limits for `tier`, merged over the built-in defaults."
  @spec limits_for(tier(), keyword()) :: keyword()
  def limits_for(tier, opts \\ []) do
    configured = Application.get_env(:arcada, __MODULE__, [])

    @defaults
    |> Keyword.fetch!(tier)
    |> Keyword.merge(Keyword.get(configured, tier, []))
    |> Keyword.merge(Keyword.take(opts, [:per_minute, :per_day]))
  end
end
