defmodule OQueMudouWeb.ActLive do
  @moduledoc """
  Act detail: plain-language summary + life-domains, with the official source,
  PDF citation, and full legal text always one click away — plus the private
  "marcar como validado" toggle (the human safety net before anything is trusted).
  See `docs/PLAN.md` build order #4.
  """
  use OQueMudouWeb, :live_view

  alias OQueMudou.Register

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    act = Register.get_act!(id)
    {:ok, assign(socket, act: act, summary: latest_summary(act), show_full: false)}
  end

  @impl true
  def handle_event("toggle_validated", _params, socket) do
    case socket.assigns.summary do
      nil ->
        {:noreply, socket}

      summary ->
        validate? = is_nil(summary.validated_at)
        {:ok, updated} = Register.set_validated(summary, validate?)

        msg =
          if validate?,
            do: "Resumo marcado como validado.",
            else: "Validação removida."

        {:noreply, socket |> assign(summary: updated) |> put_flash(:info, msg)}
    end
  end

  def handle_event("toggle_full", _params, socket) do
    {:noreply, assign(socket, show_full: !socket.assigns.show_full)}
  end

  defp latest_summary(%{summaries: summaries}) do
    summaries |> Enum.sort_by(& &1.generated_at, {:desc, DateTime}) |> List.first()
  end

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
        <p :if={@act.tipo} class="text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">
          {@act.tipo}
        </p>
        <h1 class="mt-1.5 text-pretty font-display text-[1.75rem] font-semibold leading-tight text-ink sm:text-[2.25rem]">
          {@act.title || @act.tipo}
        </h1>
        <p class="mt-2 text-sm text-muted">
          {@act.emitter}
          <span :if={@act.published_at}>· {format_date(@act.published_at)}</span>
        </p>
      </header>

      <section class="mt-7">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="flex items-center gap-2 text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">
            Em linguagem simples
            <.provenance_badge summary={@summary} />
          </h2>
          <.validation_control summary={@summary} />
        </div>

        <p
          :if={@summary}
          class="mt-4 max-w-reading text-pretty font-serif text-[1.25rem] leading-relaxed text-ink"
        >
          {@summary.plain_text}
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
            <.icon name="hero-arrow-top-right-on-square-micro" class="size-4 text-muted" /> Fonte oficial
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
          {raw(@act.full_text)}
        </div>
      </section>
    </div>
    """
  end

  attr :summary, :map, default: nil

  defp validation_control(%{summary: nil} = assigns), do: ~H""

  defp validation_control(assigns) do
    ~H"""
    <button
      phx-click="toggle_validated"
      aria-pressed={to_string(not is_nil(@summary.validated_at))}
      class={[
        "inline-flex min-h-[2.25rem] items-center gap-1.5 rounded-md px-3 py-1.5 text-[0.8125rem] font-medium",
        "transition-colors duration-150 ease-out-quart",
        @summary.validated_at && "bg-state-verified-bg text-state-verified-ink hover:opacity-80",
        !@summary.validated_at &&
          "border border-border text-muted hover:border-muted hover:text-ink"
      ]}
    >
      <.icon :if={@summary.validated_at} name="hero-check-mini" class="size-4" />
      {if @summary.validated_at, do: "Validado", else: "Marcar como validado"}
    </button>
    """
  end

  defp model_line(%{model: model, prompt_version: pv}) when is_binary(model),
    do: "Gerado por #{model} · prompt #{pv}"

  defp model_line(_), do: "Resumo manual"

  @months ~w(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro)
  defp format_date(%Date{} = d), do: "#{d.day} de #{Enum.at(@months, d.month - 1)} de #{d.year}"
end
