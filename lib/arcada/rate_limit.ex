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
  @day :timer.hours(24)

  @defaults [
    anon: [per_minute: 20, per_day: 200],
    user: [per_minute: 120, per_day: 2_000]
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
