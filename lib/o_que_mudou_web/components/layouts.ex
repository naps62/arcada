defmodule OQueMudouWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use OQueMudouWeb, :controller` and
  `use OQueMudouWeb, :live_view`.
  """
  use OQueMudouWeb, :html

  embed_templates "layouts/*"

  @doc """
  Umami analytics config, or `nil` when not configured.

  Returns `%{script_url: ..., website_id: ...}` only when both
  `UMAMI_SCRIPT_URL` and `UMAMI_WEBSITE_ID` are set (see `config/runtime.exs`).
  When `nil` the root layout omits the tracking tag entirely — so dev and the
  VPN-gated deployment stay untracked, and analytics only loads once the public
  build is configured.
  """
  def umami do
    cfg = Application.get_env(:o_que_mudou, :umami, [])

    case {cfg[:script_url], cfg[:website_id]} do
      {url, id} when is_binary(url) and is_binary(id) ->
        %{script_url: url, website_id: id}

      _ ->
        nil
    end
  end
end
