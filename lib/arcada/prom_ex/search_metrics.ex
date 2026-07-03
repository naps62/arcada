defmodule Arcada.PromEx.SearchMetrics do
  @moduledoc """
  Prometheus counter for search queries (issue #32), tagged by tier and whether
  the semantic leg actually ran. This is the retention/usage signal accounts are
  meant to drive: `anon` vs `user` volume shows the signup funnel, and
  `degraded` (over rate limit → FTS-only) shows how often the nudge fires.

  Emitted from `Arcada.Search.for_visitor/2` as `[:arcada, :search, :query]`.
  """

  use PromEx.Plugin

  @event [:arcada, :search, :query]

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :arcada_search_event_metrics,
      [
        counter(
          [:arcada, :search, :query, :total],
          event_name: @event,
          description: "Total search queries, by caller tier and whether semantic ran.",
          tags: [:tier, :degraded]
        )
      ]
    )
  end
end
