defmodule OQueMudou.PromEx.SearchMetrics do
  @moduledoc """
  Prometheus counter for search queries (issue #32), tagged by tier and whether
  the semantic leg actually ran. This is the retention/usage signal accounts are
  meant to drive: `anon` vs `user` volume shows the signup funnel, and
  `degraded` (over rate limit → FTS-only) shows how often the nudge fires.

  Emitted from `OQueMudouWeb.RegisterLive` as `[:o_que_mudou, :search, :query]`.
  """

  use PromEx.Plugin

  @event [:o_que_mudou, :search, :query]

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :o_que_mudou_search_event_metrics,
      [
        counter(
          [:o_que_mudou, :search, :query, :total],
          event_name: @event,
          description: "Total search queries, by caller tier and whether semantic ran.",
          tags: [:tier, :degraded]
        )
      ]
    )
  end
end
