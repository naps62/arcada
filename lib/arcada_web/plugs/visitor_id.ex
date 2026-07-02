defmodule ArcadaWeb.Plugs.VisitorId do
  @moduledoc """
  Ensures every browser session carries an opaque `"visitor_id"` (issue #32).

  Anonymous rate limiting keys on this id. It *must* be minted here, in the HTTP
  request, so it lands in the session cookie and is present when the LiveView
  socket connects (a LiveView can't set a cookie over the websocket). Once set it
  is never rotated, so a visitor's per-day search budget survives navigation.

  It is not identity and not a bot defence — clearing cookies mints a fresh one.
  Real client-IP keying is deferred to RemoteIp (issue #43); until then this
  steers humans toward signing in rather than stopping scripts.
  """

  import Plug.Conn

  @session_key "visitor_id"

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, @session_key) do
      nil -> put_session(conn, @session_key, generate_id())
      _id -> conn
    end
  end

  defp generate_id, do: 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64()
end
