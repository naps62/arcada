defmodule OQueMudouWeb.SearchLive do
  @moduledoc """
  Semantic search over summaries (issue #27): describe the change you're
  looking for in plain language — no exact keywords needed. Debounced input,
  brute-force cosine over bge-m3 embeddings (`OQueMudou.Search`).
  """
  use OQueMudouWeb, :live_view

  alias OQueMudou.{Register, Search}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, query: "", results: nil, page_title: "Pesquisar")}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    query = String.trim(query)
    results = if query == "", do: nil, else: Search.search(query)
    {:noreply, assign(socket, query: query, results: results)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <h1 class="font-display text-2xl font-semibold leading-snug text-ink">Pesquisar</h1>
      <p class="mt-1.5 max-w-reading text-sm text-muted">
        Descreve a mudança que procuras — ex.: apoios ao arrendamento jovem, alterações ao IRS…
      </p>

      <form id="search-form" phx-change="search" class="mt-5" phx-submit="search">
        <label for="search-q" class="sr-only">Pesquisar</label>
        <div class="relative">
          <.icon
            name="hero-magnifying-glass-micro"
            class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted"
          />
          <input
            type="text"
            id="search-q"
            name="q"
            value={@query}
            phx-debounce="300"
            autocomplete="off"
            placeholder="Descreve a mudança que procuras…"
            class="w-full rounded-md border border-border bg-surface py-2.5 pl-9 pr-3 text-sm text-ink placeholder:text-muted focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
          />
        </div>
      </form>

      <p :if={@results == []} class="mt-10 text-center text-sm text-muted">
        Nada encontrado para "{@query}".
      </p>

      <ul :if={@results not in [nil, []]} class="mt-6 divide-y divide-border">
        <li :for={act <- @results}>
          <.act_entry act={act} summary={Register.published_summary(act)} />
        </li>
      </ul>
    </section>
    """
  end
end
