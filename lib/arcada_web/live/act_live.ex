defmodule ArcadaWeb.ActLive do
  @moduledoc """
  Act detail: plain-language summary + life-domains, with the official source,
  PDF citation, and full legal text always one click away.
  See `docs/PLAN.md` build order #4.
  """
  use ArcadaWeb, :live_view

  alias Arcada.Register
  alias Arcada.Register.Summary
  alias ArcadaWeb.SEO

  # Public act pages key on the stable `dre_id`; the `:slug` segment is
  # decorative (ignored here) and reconciled by the canonical <link>.
  @impl true
  def mount(%{"dre_id" => dre_id}, _session, socket) do
    act = Register.get_act_by_dre_id!(dre_id)
    summary = Register.published_summary(act)

    {:ok,
     socket
     |> assign(act: act, summary: summary, show_full: false)
     |> assign(SEO.metadata_for({:act, act, summary}))}
  end

  @impl true
  def handle_event("toggle_full", _params, socket) do
    {:noreply, assign(socket, show_full: !socket.assigns.show_full)}
  end

  # full_text is scraped DRE HTML (untrusted); scrub to an allowlist before raw/1.
  # html5 keeps legal formatting (tables/headings/lists), drops scripts + handlers.
  defp safe_full_text(nil), do: nil
  defp safe_full_text(html), do: HtmlSanitizeEx.html5(html)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-2">
      <.link
        navigate={~p"/"}
        class="inline-flex items-center gap-1 text-sm text-muted hover:text-primary hover:underline"
      >
        <.icon name="hero-arrow-left-micro" class="size-4" /> Voltar ao registo
      </.link>

      <header class="mt-6 border-b-2 border-rule-strong pb-5">
        <p
          :if={@act.tipo}
          class="text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted"
        >
          {@act.tipo}
        </p>
        <h1 class="mt-1.5 text-pretty font-display text-[1.75rem] font-semibold leading-tight text-ink sm:text-[2.25rem]">
          {(@summary && Summary.strip_terms(@summary.headline)) || @act.title || @act.tipo}
        </h1>
        <p :if={@summary && @summary.headline} class="mt-1.5 text-sm text-muted">
          {@act.title || @act.tipo}
        </p>
        <p class="mt-2 text-sm text-muted">
          {@act.emitter}
          <span :if={@act.published_at}>· {format_date(@act.published_at)}</span>
        </p>
      </header>

      <section class="mt-7">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="flex items-center gap-2 text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">
            Em linguagem simples
          </h2>
        </div>

        <p
          :if={@summary}
          class="mt-4 max-w-reading text-pretty font-serif text-[1.25rem] leading-relaxed text-ink"
        >
          {Summary.strip_terms(@summary.plain_text)}
        </p>
        <p :if={is_nil(@summary)} class="mt-4 font-serif text-lg italic text-muted">
          Ainda sem resumo em linguagem simples.
        </p>

        <div :if={@summary && @summary.domains != []} class="mt-5 flex flex-wrap gap-1.5">
          <.domain_tag :for={d <- @summary.domains} label={to_string(d)} />
        </div>

        <p :if={@summary} class="mt-4 text-xs text-muted">
          {model_line(@summary)}
        </p>
      </section>

      <section class="mt-8 border-t border-border pt-5">
        <h2 class="sr-only">Fontes oficiais</h2>
        <div class="flex flex-wrap gap-2 text-sm">
          <a
            :if={@act.source_url}
            href={@act.source_url}
            target="_blank"
            rel="noopener"
            class="inline-flex min-h-[2.75rem] items-center gap-1.5 rounded-md border border-border px-3.5 py-2 font-medium text-ink hover:bg-surface"
          >
            <.icon name="hero-arrow-top-right-on-square-micro" class="size-4 text-muted" />
            Fonte oficial
          </a>
          <a
            :if={@act.pdf_url}
            href={@act.pdf_url}
            target="_blank"
            rel="noopener"
            class="inline-flex min-h-[2.75rem] items-center gap-1.5 rounded-md border border-border px-3.5 py-2 font-medium text-ink hover:bg-surface"
          >
            <.icon name="hero-document-text-micro" class="size-4 text-muted" /> PDF (citação)
          </a>
          <button
            :if={@act.full_text}
            phx-click="toggle_full"
            aria-expanded={to_string(@show_full)}
            class="inline-flex min-h-[2.75rem] items-center gap-1.5 rounded-md border border-border px-3.5 py-2 font-medium text-ink hover:bg-surface"
          >
            <.icon
              name={if @show_full, do: "hero-chevron-up-micro", else: "hero-chevron-down-micro"}
              class="size-4 text-muted"
            />
            {if @show_full, do: "Ocultar texto integral", else: "Ver texto integral"}
          </button>
        </div>
      </section>

      <section :if={@show_full && @act.full_text} class="mt-6 border-t border-border pt-5">
        <h2 class="text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">
          Texto integral
        </h2>
        <div class="prose prose-sm mt-3 max-w-none font-serif text-ink prose-headings:font-display prose-headings:text-ink prose-a:text-primary">
          {raw(safe_full_text(@act.full_text))}
        </div>
      </section>
    </div>
    """
  end

  # The provider name (e.g. "claude-ssh") is an internal routing detail and must
  # never be surfaced. Ranked summaries lead with the embeddings model that
  # scored the sections, piped into the LLM: "bge-m3 embeddings > claude-sonnet-4-6".
  defp model_line(%{text_strategy: "rank", ranker_model: r, model: model})
       when is_binary(r) and is_binary(model),
       do: "#{r} embeddings > #{model}"

  defp model_line(%{model: model} = s) when is_binary(model),
    do: join_meta([model, strategy_meta(s)])

  # Legacy rows may have no model recorded — show nothing rather than a label.
  defp model_line(_), do: nil

  defp join_meta(parts), do: parts |> Enum.reject(&is_nil/1) |> Enum.join(" · ")

  # Which slice of an oversized diploma fed the summary. nil when the whole act
  # fit (`text_strategy` "full" or a legacy row) — nothing worth noting. The
  # ranked case names its embeddings model in `model_line/1` instead.
  defp strategy_meta(%{text_strategy: "rank"}), do: "secções relevantes"
  defp strategy_meta(%{text_strategy: "truncate"}), do: "início do texto"
  defp strategy_meta(_), do: nil

  @months ~w(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro)
  defp format_date(%Date{} = d), do: "#{d.day} de #{Enum.at(@months, d.month - 1)} de #{d.year}"
end
