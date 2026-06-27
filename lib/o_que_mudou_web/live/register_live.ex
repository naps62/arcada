defmodule OQueMudouWeb.RegisterLive do
  @moduledoc """
  The private register: acts grouped by publication date, with a static
  life-domain filter. Each act shows its plain-language summary (labelled
  🤖 não revisto until a human validates it). See `docs/PLAN.md` build order #4.
  """
  use OQueMudouWeb, :live_view

  alias OQueMudou.Register

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "O que mudou",
       domains: Register.life_domains(),
       domain_counts: Register.domain_counts()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    domain = params["domain"]
    groups = Register.list_acts(domain: domain, limit: 300) |> group_by_date()
    {:noreply, assign(socket, active_domain: domain, groups: groups)}
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
    <div class="mx-auto max-w-3xl px-4 py-8">
      <header class="mb-6">
        <h1 class="text-2xl font-bold text-zinc-900">O que mudou</h1>
        <p class="text-sm text-zinc-500">
          Diário da República, Série I — em linguagem simples.
          <span class="italic">Isto não é aconselhamento jurídico.</span>
        </p>
      </header>

      <nav class="mb-8 flex flex-wrap gap-2" aria-label="Filtrar por domínio">
        <.domain_pill label="Tudo" patch={~p"/"} active={is_nil(@active_domain)} />
        <.domain_pill
          :for={d <- @domains}
          label={d}
          count={@domain_counts[d]}
          patch={~p"/?#{[domain: d]}"}
          active={@active_domain == d}
        />
      </nav>

      <p :if={@groups == []} class="rounded-lg bg-zinc-50 p-6 text-center text-zinc-500">
        Nada a mostrar <span :if={@active_domain}>para o domínio "{@active_domain}"</span>.
      </p>

      <section :for={{date, acts} <- @groups} class="mb-8">
        <h2 class="mb-3 border-b border-zinc-200 pb-1 text-sm font-semibold uppercase tracking-wide text-zinc-500">
          {format_date(date)}
        </h2>
        <ul class="space-y-4">
          <li :for={act <- acts} class="rounded-lg border border-zinc-200 p-4">
            <.act_row act={act} summary={latest_summary(act)} />
          </li>
        </ul>
      </section>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :patch, :string, required: true
  attr :active, :boolean, default: false
  attr :count, :integer, default: nil

  defp domain_pill(assigns) do
    ~H"""
    <.link
      patch={@patch}
      class={[
        "rounded-full px-3 py-1 text-sm font-medium transition",
        @active && "bg-zinc-900 text-white",
        !@active && "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
      ]}
    >
      {@label}<span :if={@count} class="ml-1 text-xs opacity-70">{@count}</span>
    </.link>
    """
  end

  attr :act, :map, required: true
  attr :summary, :map, default: nil

  defp act_row(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-3">
      <h3 class="font-medium text-zinc-900">{@act.title || @act.tipo}</h3>
      <.status_badge summary={@summary} />
    </div>
    <p :if={@act.emitter} class="mt-0.5 text-xs text-zinc-500">{@act.emitter}</p>

    <p :if={@summary} class="mt-2 text-sm text-zinc-700">{@summary.plain_text}</p>
    <p :if={is_nil(@summary)} class="mt-2 text-sm italic text-zinc-400">Resumo por gerar.</p>

    <div :if={@summary && @summary.domains != []} class="mt-2 flex flex-wrap gap-1">
      <span
        :for={d <- @summary.domains}
        class="rounded bg-zinc-100 px-2 py-0.5 text-xs text-zinc-600"
      >
        {d}
      </span>
    </div>

    <div class="mt-2 flex gap-3 text-xs">
      <a
        :if={@act.source_url}
        href={@act.source_url}
        target="_blank"
        class="text-zinc-500 hover:underline"
      >
        fonte oficial
      </a>
      <a :if={@act.pdf_url} href={@act.pdf_url} target="_blank" class="text-zinc-500 hover:underline">
        PDF
      </a>
    </div>
    """
  end

  attr :summary, :map, default: nil

  defp status_badge(%{summary: nil} = assigns), do: ~H""

  defp status_badge(%{summary: %{validated_at: at}} = assigns) when not is_nil(at) do
    ~H"""
    <span class="shrink-0 rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-800">
      ✓ validado
    </span>
    """
  end

  defp status_badge(assigns) do
    ~H"""
    <span class="shrink-0 rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-800">
      🤖 não revisto
    </span>
    """
  end

  @months ~w(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro)
  defp format_date(%Date{} = d), do: "#{d.day} de #{Enum.at(@months, d.month - 1)} de #{d.year}"
end
