defmodule OQueMudouWeb.Turnstile do
  @moduledoc """
  Cloudflare Turnstile bot check for the public signup form.

  Config lives under `OQueMudouWeb.Turnstile` (`:site_key` is public and
  rendered into the widget, `:secret_key` is server-only). Both come from env
  at runtime (`TURNSTILE_SITE_KEY` / `TURNSTILE_SECRET_KEY`, see
  `config/runtime.exs`). When no keys are set — dev/test by default —
  `enabled?/0` is false, the widget is not rendered and `verify/1` no-ops so
  the mailbox preview flow keeps working.
  """

  @siteverify "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  @doc "True when a site key is configured (prod with Turnstile env set)."
  def enabled?, do: not is_nil(site_key())

  @doc "Public site key for the widget, or nil when disabled."
  def site_key, do: config()[:site_key]

  defp secret_key, do: config()[:secret_key]

  defp config, do: Application.get_env(:o_que_mudou, __MODULE__, [])

  @doc """
  Validates a Turnstile response token against Cloudflare's siteverify API.

  Returns `:ok` when disabled (no keys) or when Cloudflare confirms the token,
  `:error` on a missing/invalid token or any API failure.
  """
  def verify(token) do
    cond do
      not enabled?() ->
        :ok

      is_nil(token) or token == "" ->
        :error

      true ->
        case Req.post(@siteverify,
               form: [secret: secret_key(), response: token],
               retry: false,
               receive_timeout: 5_000
             ) do
          {:ok, %Req.Response{status: 200, body: %{"success" => true}}} -> :ok
          _ -> :error
        end
    end
  end
end
