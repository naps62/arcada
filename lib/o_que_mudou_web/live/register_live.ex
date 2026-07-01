defmodule OQueMudouWeb.RegisterLive do
  @moduledoc """
  The private register: acts grouped by publication date, with a static
  life-domain filter. Each act shows its plain-language summary (labelled by its
  provenance rung until a human validates it). See `docs/PLAN.md` build order #4.
  """
  use OQueMudouWeb, :live_view

  alias OQueMudou.{Register, Search}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       front_page: true,
       domains: Register.life_domains(),
       periods: Register.periods(),
       query: "",
       search_results: nil,
       # Bumped on every completed search so the results container patches (and
       # the FlashOnResult hook fires) even when the results are identical —
       # e.g. deleting a character re-runs the search but returns the same acts.
       search_token: 0
     )}
  end

  # Live search pushes the query into the URL (`?q=…`) so results are shareable
  # and deep-linkable; `handle_params` runs the actual search. `replace: true`
  # keeps the debounced keystrokes from flooding browser history.
  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    case String.trim(query) do
      "" -> {:noreply, push_patch(socket, to: ~p"/", replace: true)}
      q -> {:noreply, push_patch(socket, to: ~p"/?#{[q: q]}", replace: true)}
    end
  end

  # The URL is the source of truth: `?q=…` is search mode (deep-linkable),
  # anything else is the filtered browse listing.
  @impl true
  def handle_params(params, _uri, socket) do
    case String.trim(params["q"] || "") do
      "" -> {:noreply, assign_browse(socket, params)}
      query -> {:noreply, assign_search(socket, query)}
    end
  end

  defp assign_search(socket, query) do
    assign(socket,
      query: query,
      search_results: Search.search(query),
      search_token: socket.assigns.search_token + 1,
      page_title: "Pesquisa: #{query}"
    )
  end

  defp assign_browse(socket, params) do
    domain = params["domain"]
    period = Register.fetch_period(params["period"])
    acts = Register.list_acts(domain: domain, period: period, limit: 300)

    assign(socket,
      query: "",
      search_results: nil,
      active_domain: domain,
      active_period: period,
      # Each axis's badges reflect the *other* axis's selection.
      domain_counts: Register.domain_counts(period: period),
      period_counts: Register.period_counts(domain: domain),
      groups: group_by_date(acts),
      total: length(acts),
      page_title: page_title(domain, period)
    )
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
    <%!-- The hero's closing element: search is a first-class masthead affordance
         (Arcada = the arcade you come to look something up in). Bold field +
         the one primary action the palette allows, then a heavy rule closes the
         whole masthead before the filters/results. --%>
    <section class="pb-7 pt-4 sm:pb-9 sm:pt-6">
      <form id="search-form" phx-change="search" phx-submit="search">
        <label for="search-q" class="sr-only">Pesquisar diplomas</label>
        <div class="flex items-stretch gap-2 sm:gap-2.5">
          <div class="relative flex-1">
            <.icon
              name="hero-magnifying-glass"
              class="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-muted"
            />
            <input
              type="text"
              id="search-q"
              name="q"
              value={@query}
              phx-debounce="300"
              autocomplete="off"
              placeholder="Descreve a mudança que procuras…"
              class="h-14 w-full rounded-md border-2 border-border bg-surface pl-12 pr-4 text-base text-ink transition-colors duration-150 ease-out-quart placeholder:text-muted focus:border-primary focus:outline-none focus:ring-4 focus:ring-primary/15 sm:h-16 sm:pl-14 sm:text-lg"
            />
          </div>
          <%!-- Desktop only: a strong primary affordance. On mobile the live
               (debounced) field + Enter is enough, and a second search glyph
               beside the field's own icon would just be redundant. --%>
          <button
            type="submit"
            class="relative hidden shrink-0 items-center justify-center rounded-md bg-primary px-8 text-base font-semibold text-primary-fg transition-colors duration-150 ease-out-quart hover:bg-primary-hover focus:outline-none focus:ring-4 focus:ring-primary/25 sm:inline-flex"
          >
            <%!-- The label reserves the button width; while a search request is in
                 flight the spinner overlays it centered, so the button doesn't
                 resize. Loading classes are set on the form by phx-change/submit. --%>
            <span class="phx-change-loading:opacity-0 phx-submit-loading:opacity-0">
              Pesquisar
            </span>
            <span class="pointer-events-none absolute inset-0 hidden items-center justify-center phx-change-loading:flex phx-submit-loading:flex">
              <.icon name="hero-arrow-path" class="size-5 animate-spin" />
            </span>
          </button>
        </div>
        <p class="mt-3 flex items-center justify-center gap-1.5 text-center text-xs text-muted">
          <.icon name="hero-information-circle-micro" class="size-3.5 shrink-0" />
          <span>Pesquisa por significado — não precisas das palavras exatas.</span>
        </p>
      </form>
    </section>

    <div class="border-b-2 border-rule-strong"></div>

    <div
      :if={@search_results}
      id="search-results"
      phx-hook="FlashOnResult"
      data-token={@search_token}
    >
      <p :if={@search_results == []} class="border-b border-border py-16 text-center">
        <.icon name="hero-document-magnifying-glass" class="mx-auto size-8 text-muted" />
        <span class="mt-3 block font-display text-lg text-ink">
          Nada encontrado para "{@query}".
        </span>
      </p>
      <ul :if={@search_results != []} class="mt-2 divide-y divide-border">
        <li :for={act <- @search_results}>
          <.act_entry
            act={act}
            summary={Register.published_summary(act)}
            date={act.edition.date}
          />
        </li>
      </ul>
    </div>

    <div :if={!@search_results}>
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
            <time datetime={Date.to_iso8601(date)}>{format_pt_date(date)}</time>
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
    </div>
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
end
