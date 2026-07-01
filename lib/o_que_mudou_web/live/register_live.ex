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
       front_page: true,
       domains: Register.life_domains(),
       periods: Register.periods()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    domain = params["domain"]
    period = Register.fetch_period(params["period"])
    acts = Register.list_acts(domain: domain, period: period, limit: 300)
    groups = group_by_date(acts)

    {:noreply,
     assign(socket,
       active_domain: domain,
       active_period: period,
       # Each axis's badges reflect the *other* axis's selection.
       domain_counts: Register.domain_counts(period: period),
       period_counts: Register.period_counts(domain: domain),
       groups: groups,
       total: length(acts),
       page_title: page_title(domain, period)
     )}
  end

  # Group acts by their edition's publication date, newest day first.
  defp group_by_date(acts) do
    acts
    |> Enum.group_by(& &1.edition.date)
    |> Enum.sort_by(fn {date, _} -> date end, {:desc, Date})
  end

  # Show the published summary (falls back to the latest) so the homepage
  # reflects the admin's published choice.
  defp latest_summary(%{summaries: summaries} = act) when is_list(summaries),
    do: OQueMudou.Register.published_summary(act)

  defp latest_summary(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <section aria-label="Filtros" class="border-b border-border">
      <.filter_row id="filtro-quando" label="Quando">
        <li>
          <.section_link
            label="Tudo"
            patch={filter_path(@active_domain, nil)}
            active={is_nil(@active_period)}
          />
        </li>
        <li :for={p <- @periods}>
          <.section_link
            label={period_label(p)}
            count={@period_counts[p]}
            patch={filter_path(@active_domain, p)}
            active={@active_period == p}
          />
        </li>
      </.filter_row>

      <.filter_row id="filtro-tema" label="Tema" class="border-t border-border">
        <li>
          <.section_link
            label="Tudo"
            patch={filter_path(nil, @active_period)}
            active={is_nil(@active_domain)}
          />
        </li>
        <li :for={d <- @domains}>
          <.section_link
            label={d}
            count={@domain_counts[d]}
            patch={filter_path(d, @active_period)}
            active={@active_domain == d}
          />
        </li>
      </.filter_row>
    </section>

    <%!-- Only while filtering: this is the filter's feedback + reset, not a
         page-wide tally (a grand total clashes with the per-day section counts). --%>
    <div
      :if={@groups != [] && (@active_domain || @active_period)}
      class="flex items-baseline justify-between gap-4 border-b border-border py-2.5"
    >
      <p class="text-[0.6875rem] uppercase tracking-[0.08em] text-muted">
        <span class="font-semibold tabular-nums text-ink">{@total}</span>
        {if @total == 1, do: "diploma", else: "diplomas"}
        <span :if={@active_period}>
          · {String.downcase(period_label(@active_period))}
        </span><span :if={@active_domain}>
          · {@active_domain}
        </span>
      </p>
      <.link
        patch={~p"/"}
        class="inline-flex shrink-0 items-center gap-1 text-[0.6875rem] font-semibold uppercase tracking-[0.08em] text-muted transition-colors duration-150 ease-out-quart hover:text-primary"
      >
        <.icon name="hero-x-mark-micro" class="size-3.5" /> limpar
      </.link>
    </div>

    <div :if={@groups == []} class="border-b border-border py-16 text-center">
      <.icon name="hero-document-magnifying-glass" class="mx-auto size-8 text-muted" />
      <p class="mt-3 font-display text-lg text-ink">
        Nada a mostrar<span :if={@active_domain}> em "{@active_domain}"</span><span :if={
          @active_period
        }> {period_label(@active_period) |> String.downcase()}</span>.
      </p>
      <p :if={@active_domain || @active_period} class="mt-1 text-sm text-muted">
        Experimenta alargar o período ou limpar os filtros.
      </p>
      <.link
        :if={@active_domain || @active_period}
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

  # A labeled filter axis: a fixed-width rubric in the left gutter (the row's
  # accessible name) and a wrapping bar of section links. Label stacks above the
  # bar on narrow screens, sits beside it from `sm` up.
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  defp filter_row(assigns) do
    ~H"""
    <div class={["sm:flex sm:items-baseline sm:gap-x-4", @class]}>
      <span
        id={@id}
        class="block pt-2.5 text-[0.625rem] font-semibold uppercase tracking-[0.14em] text-muted sm:w-[4.5rem] sm:shrink-0 sm:py-2.5"
      >
        {@label}
      </span>
      <nav aria-labelledby={@id} class="min-w-0 sm:flex-1">
        <ul class="flex flex-wrap items-baseline gap-x-5">
          {render_slot(@inner_block)}
        </ul>
      </nav>
    </div>
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
      <span class={[
        "border-b-2 pb-0.5 transition-colors duration-150 ease-out-quart",
        @active && "border-ink",
        !@active && "border-transparent group-hover:border-border"
      ]}>
        {@label}
      </span>
      <span
        :if={@count}
        class={[
          "text-[0.625rem] font-normal normal-case tabular-nums",
          @active && "text-ink",
          !@active && "text-muted"
        ]}
      >
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
        <div class="mt-0.5 flex shrink-0 flex-col items-end gap-1">
          <.provenance_badge summary={@summary} />
        </div>
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

  defp period_label(:semana), do: "Esta semana"
  defp period_label(:mes), do: "Este mês"
  defp period_label(:ano), do: "Este ano"

  # Build a register path preserving both filter axes; nil values are dropped so
  # the URL stays clean (e.g. "/", "/?domain=fiscal", "/?domain=fiscal&period=mes").
  defp filter_path(domain, period) do
    params =
      []
      |> put_param(:domain, domain)
      |> put_param(:period, period && Atom.to_string(period))

    ~p"/?#{params}"
  end

  defp put_param(params, _key, nil), do: params
  defp put_param(params, key, value), do: params ++ [{key, value}]

  defp page_title(nil, nil), do: nil
  defp page_title(domain, nil), do: to_string(domain)
  defp page_title(nil, period), do: period_label(period)
  defp page_title(domain, period), do: "#{domain} · #{period_label(period)}"

  @months ~w(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro)
  defp format_date(%Date{} = d), do: "#{d.day} de #{Enum.at(@months, d.month - 1)} de #{d.year}"
end
