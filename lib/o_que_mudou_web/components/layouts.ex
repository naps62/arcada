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
  Three-way theme control: auto / light / dark.

  Client-only — a small LiveView hook (`ThemeToggle`) persists the choice in
  `localStorage` and drives `window.__applyTheme/1` (defined inline in the root
  layout for no-flash startup). The server always renders the "auto" default;
  `phx-update="ignore"` hands the subtree to the hook so its live state survives
  re-renders and navigation.
  """
  attr :class, :string, default: nil

  def theme_toggle(assigns) do
    ~H"""
    <div
      id="theme-toggle"
      phx-hook="ThemeToggle"
      phx-update="ignore"
      role="group"
      aria-label="Tema"
      class={[
        "flex items-center gap-0.5 rounded-full border border-border bg-surface/50 p-0.5",
        @class
      ]}
    >
      <button
        :for={
          {value, icon, label} <- [
            {"auto", "hero-computer-desktop-micro", "Automático (segue o sistema)"},
            {"light", "hero-sun-micro", "Claro"},
            {"dark", "hero-moon-micro", "Escuro"}
          ]
        }
        type="button"
        data-theme-option={value}
        aria-pressed="false"
        title={label}
        aria-label={"Tema: #{label}"}
        class="flex size-7 items-center justify-center rounded-full text-muted transition-colors duration-150 ease-out-quart hover:text-ink aria-pressed:bg-ink aria-pressed:text-bg"
      >
        <.icon name={icon} class="size-3.5" />
      </button>
    </div>
    """
  end

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
