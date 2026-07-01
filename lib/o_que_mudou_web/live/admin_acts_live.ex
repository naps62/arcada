defmodule OQueMudouWeb.AdminActsLive do
  @moduledoc """
  Admin acts browser (`/admin/acts`): traverse acts newest-first, filter by life
  domain and date window, and see at a glance how many summaries each act has and
  which provider/model is canonical. Each row links to `AdminActLive` for the
  side-by-side comparison. See issue #30.
  """
  use OQueMudouWeb, :live_view_admin

  alias OQueMudou.Register

  @limit 200

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       domains: Register.life_domains(),
       periods: Register.periods(),
       limit: @limit
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    domain = params["domain"]
    period = Register.fetch_period(params["period"])
    acts = Register.admin_list_acts(domain: domain, period: period, limit: @limit)

    {:noreply,
     assign(socket,
       acts: acts,
       active_domain: domain,
       active_period: period,
       page_title: "Acts"
     )}
  end

  # Both filters live in the URL so the view is deep-linkable and the sidebar can
  # highlight it. Changing either select patches the params; `handle_params`
  # re-runs the query.
  @impl true
  def handle_event("filter", params, socket) do
    domain = emptyish(params["domain"])
    period = emptyish(params["period"])

    query = Enum.reject([domain: domain, period: period], fn {_k, v} -> is_nil(v) end)

    {:noreply, push_patch(socket, to: ~p"/admin/acts?#{query}")}
  end

  defp emptyish(v) when v in ["", nil], do: nil
  defp emptyish(v), do: v

  @impl true
  def render(assigns) do
    ~H"""
    <header class="border-b-2 border-rule-strong pb-4">
      <h1 class="font-display text-[1.75rem] font-semibold leading-tight text-ink">Acts</h1>
      <p class="mt-2 max-w-prose text-sm leading-relaxed text-muted">
        Browse every act, newest first. Open one to compare its summaries side-by-side and pick the
        canonical one.
      </p>
    </header>

    <form id="acts-filter" phx-change="filter" class="mt-6 flex flex-wrap items-end gap-3">
      <div>
        <label class="block text-xs text-muted">Life domain</label>
        <select
          name="domain"
          class="mt-1 rounded-md border border-border bg-bg px-2 py-1.5 text-sm text-ink focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
        >
          <option value="">All domains</option>
          <option :for={d <- @domains} value={d} selected={@active_domain == d}>{d}</option>
        </select>
      </div>
      <div>
        <label class="block text-xs text-muted">Period</label>
        <select
          name="period"
          class="mt-1 rounded-md border border-border bg-bg px-2 py-1.5 text-sm text-ink focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
        >
          <option value="">All time</option>
          <option
            :for={p <- @periods}
            value={p}
            selected={@active_period == p}
          >
            {period_label(p)}
          </option>
        </select>
      </div>
      <.link
        :if={@active_domain || @active_period}
        patch={~p"/admin/acts"}
        class="pb-1.5 text-sm font-medium text-muted hover:text-primary hover:underline"
      >
        Clear
      </.link>
    </form>

    <section class="mt-6">
      <h2 class="flex items-baseline justify-between border-b-2 border-rule-strong pb-2 text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">
        <span>
          Acts <span :if={@acts != []} class="ml-1 font-normal tabular-nums">{length(@acts)}</span>
        </span>
        <span :if={length(@acts) >= @limit} class="font-normal normal-case tracking-normal">
          showing first {@limit}
        </span>
      </h2>

      <p :if={@acts == []} class="mt-4 text-sm text-muted">No acts match these filters.</p>

      <ul :if={@acts != []} class="mt-1 divide-y divide-border">
        <li :for={act <- @acts} class="py-3.5">
          <.link
            navigate={~p"/admin/acts/#{act.id}"}
            class="group flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1"
          >
            <div class="min-w-0 flex-1">
              <p class="truncate font-display text-base text-ink group-hover:text-primary group-hover:underline">
                {act.title || act.tipo || "—"}
              </p>
              <p class="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-muted">
                <span :if={act.tipo}>{act.tipo}</span>
                <span :if={act.published_at} class="tabular-nums">
                  · {Date.to_iso8601(act.published_at)}
                </span>
                <span>· {canonical_label(act)}</span>
              </p>
            </div>
            <div class="flex shrink-0 items-center gap-2">
              <.status_badge act={act} />
              <span class="tabular-nums text-xs text-muted">
                {summary_count(act)} {if summary_count(act) == 1, do: "summary", else: "summaries"}
              </span>
            </div>
          </.link>
        </li>
      </ul>
    </section>
    """
  end

  defp summary_count(%{summaries: s}) when is_list(s), do: length(s)
  defp summary_count(_), do: 0

  # Which provider/model currently drives the public page for this act.
  defp canonical_label(act) do
    case Register.published_summary(act) do
      nil -> "no summary"
      summary -> "#{provider_name(summary)} · #{summary.model || "—"}"
    end
  end

  defp provider_name(%{provider: %{name: name}}), do: name
  defp provider_name(_), do: "—"

  # How the canonical summary was chosen: an explicit editorial pick, an implicit
  # latest-wins default, or nothing generated yet.
  attr :act, :any, required: true

  defp status_badge(assigns) do
    assigns = assign(assigns, :state, status_state(assigns.act))

    ~H"""
    <span class={[
      "inline-flex items-center rounded-[3px] px-1.5 py-0.5 text-[0.6875rem] font-semibold uppercase tracking-[0.04em]",
      @state == :published && "bg-surface-inset text-primary",
      @state == :auto && "bg-surface-inset text-muted",
      @state == :none && "bg-surface-inset text-muted"
    ]}>
      {status_word(@state)}
    </span>
    """
  end

  defp status_state(%{published_summary_id: id}) when is_integer(id), do: :published
  defp status_state(%{summaries: [_ | _]}), do: :auto
  defp status_state(_), do: :none

  defp status_word(:published), do: "published"
  defp status_word(:auto), do: "auto"
  defp status_word(:none), do: "no summary"

  defp period_label(:semana), do: "This week"
  defp period_label(:mes), do: "This month"
  defp period_label(:ano), do: "This year"
end
