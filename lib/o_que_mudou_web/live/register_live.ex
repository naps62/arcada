defmodule OQueMudouWeb.RegisterLive do
  @moduledoc """
  The private register: acts grouped by publication date, with a static
  life-domain filter. Each act shows its plain-language summary (labelled by its
  provenance rung until a human validates it). See `docs/PLAN.md` build order #4.
  """
  use OQueMudouWeb, :live_view

  alias OQueMudou.Register

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       domains: Register.life_domains(),
       domain_counts: Register.domain_counts()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    domain = params["domain"]
    acts = Register.list_acts(domain: domain, limit: 300)
    groups = group_by_date(acts)

    {:noreply,
     assign(socket,
       active_domain: domain,
       groups: groups,
       total: length(acts),
       page_title: domain && to_string(domain)
     )}
  end

  # Group acts by their edition's publication date, newest day first.
  defp group_by_date(acts) do
    acts
    |> Enum.group_by(& &1.edition.date)
    |> Enum.sort_by(fn {date, _} -> date end, {:desc, Date})
  end

  defp latest_summary(%{summaries: summaries}) when is_list(summaries) do
    summaries
    |> Enum.sort_by(& &1.generated_at, {:desc, DateTime})
    |> List.first()
  end

  defp latest_summary(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <section class="border-b border-border pb-7 text-center">
      <h1 class="font-display text-[1.6rem] font-light italic leading-tight text-ink sm:text-[2rem]">
        Todos os dias, o que mudou<br class="hidden sm:inline" /> na lei portuguesa.
      </h1>
      <p class="mx-auto mt-3 max-w-[52ch] text-pretty text-[0.9375rem] leading-relaxed text-muted">
        Para quem muda, e a partir de quando — em linguagem simples, com a fonte
        oficial de cada alteração sempre à mão.
      </p>
      <p class="mx-auto mt-3 inline-flex items-center gap-1.5 text-xs text-muted">
        <.icon name="hero-information-circle-micro" class="size-4 shrink-0" />
        <span>Isto não é aconselhamento jurídico — um sinal, não uma autoridade.</span>
      </p>
    </section>

    <nav class="border-b border-border" aria-label="Filtrar por domínio">
      <h2 class="sr-only">Domínios</h2>
      <ul class="flex flex-wrap items-center gap-x-5 gap-y-1 py-3">
        <li>
          <.section_link label="Tudo" patch={~p"/"} active={is_nil(@active_domain)} />
        </li>
        <li :for={d <- @domains}>
          <.section_link
            label={d}
            count={@domain_counts[d]}
            patch={~p"/?#{[domain: d]}"}
            active={@active_domain == d}
          />
        </li>
      </ul>
    </nav>

    <div :if={@groups == []} class="border-b border-border py-16 text-center">
      <.icon name="hero-document-magnifying-glass" class="mx-auto size-8 text-muted" />
      <p class="mt-3 font-display text-lg text-ink">
        Nada a mostrar<span :if={@active_domain}> em "{@active_domain}"</span>.
      </p>
      <p :if={@active_domain} class="mt-1 text-sm text-muted">
        Ainda não há diplomas resumidos neste domínio.
      </p>
      <.link
        :if={@active_domain}
        patch={~p"/"}
        class="mt-4 inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline"
      >
        Ver tudo
      </.link>
    </div>

    <section :for={{date, acts} <- @groups} class="mt-8 first:mt-7">
      <div class="mb-1 flex items-baseline justify-between gap-3 border-b-2 border-rule-strong pb-1.5">
        <h2 class="font-display text-[0.8125rem] font-bold uppercase tracking-[0.08em] text-ink">
          <time datetime={Date.to_iso8601(date)}>{format_date(date)}</time>
        </h2>
        <span class="text-xs text-muted">
          {length(acts)} {if length(acts) == 1, do: "diploma", else: "diplomas"}
        </span>
      </div>
      <ul class="divide-y divide-border">
        <li :for={act <- acts}>
          <.act_entry act={act} summary={latest_summary(act)} />
        </li>
      </ul>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :patch, :string, required: true
  attr :active, :boolean, default: false
  attr :count, :integer, default: nil

  defp section_link(assigns) do
    ~H"""
    <.link
      patch={@patch}
      aria-current={@active && "true"}
      class={[
        "group inline-flex min-h-[2.25rem] items-baseline gap-1 py-2.5 text-[0.6875rem] font-semibold uppercase tracking-[0.1em]",
        "transition-colors duration-150 ease-out-quart",
        @active && "text-ink",
        !@active && "text-muted hover:text-ink",
        !@active && @count == 0 && "opacity-50"
      ]}
    >
      <span class={["pb-0.5", @active && "border-b-2 border-ink"]}>{@label}</span>
      <span :if={@count} class="text-[0.625rem] font-normal normal-case tabular-nums text-muted">
        {@count}
      </span>
    </.link>
    """
  end

  attr :act, :map, required: true
  attr :summary, :map, default: nil

  # No summary yet: a quiet, ruled one-line brief so it recedes and the
  # summarised stories carry the page. Content leads, chrome recedes.
  defp act_entry(%{summary: nil} = assigns) do
    ~H"""
    <.link
      navigate={~p"/acts/#{@act.id}"}
      class="group flex items-baseline justify-between gap-4 py-3"
    >
      <span class="min-w-0 font-display text-[0.9375rem] text-ink group-hover:text-primary">
        {@act.title || @act.tipo}
      </span>
      <span class="shrink-0 text-[0.625rem] uppercase tracking-[0.09em] text-muted">
        por gerar
      </span>
    </.link>
    """
  end

  defp act_entry(assigns) do
    ~H"""
    <article class="py-5">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <p class="text-[0.6875rem] font-semibold uppercase tracking-[0.09em] text-muted">
            {@act.emitter || @act.tipo}
          </p>
          <h3 class="mt-1.5 text-pretty font-display text-xl font-semibold leading-snug text-ink sm:text-[1.375rem]">
            <.link navigate={~p"/acts/#{@act.id}"} class="rounded-sm hover:text-primary">
              {@act.title || @act.tipo}
            </.link>
          </h3>
        </div>
        <.provenance_badge summary={@summary} class="mt-0.5" />
      </div>

      <p class="mt-2.5 max-w-reading text-pretty font-serif text-[1.0625rem] leading-relaxed text-ink">
        {@summary.plain_text}
      </p>

      <div class="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1.5">
        <div :if={@summary.domains != []} class="flex flex-wrap gap-1.5">
          <.domain_tag :for={d <- @summary.domains} label={to_string(d)} />
        </div>
        <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-[0.8125rem]">
          <a
            :if={@act.source_url}
            href={@act.source_url}
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-1 text-muted hover:text-primary hover:underline"
          >
            <.icon name="hero-arrow-top-right-on-square-micro" class="size-3.5" /> fonte oficial
          </a>
          <a
            :if={@act.pdf_url}
            href={@act.pdf_url}
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-1 text-muted hover:text-primary hover:underline"
          >
            <.icon name="hero-document-text-micro" class="size-3.5" /> PDF
          </a>
        </div>
      </div>
    </article>
    """
  end

  @months ~w(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro)
  defp format_date(%Date{} = d), do: "#{d.day} de #{Enum.at(@months, d.month - 1)} de #{d.year}"
end
