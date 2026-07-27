defmodule Arcada.Subscriptions.Matcher do
  @moduledoc """
  What a subscription actually finds in one window — the single place that turns
  "a row plus two dates" into "these acts, or none" (issue #95).

  A query subscription runs `Arcada.Search.window_matches/2`, which thresholds
  absolutely so an uneventful week returns nothing. A digest subscription skips
  search entirely and lists everything published in the window.
  """
  alias Arcada.Register
  alias Arcada.Search
  alias Arcada.Subscriptions.Subscription

  # A digest of a full month can run to hundreds of acts; the email lists this
  # many and links to the site for the rest.
  @digest_limit 40
  # A query subscription is a headline service, not an archive dump.
  @query_limit 10

  @doc "Acts to mail for `subscription` over `{from, to}`, best/newest first. `[]` = don't mail."
  def matches(subscription, window)

  def matches(%Subscription{query: nil}, {window_from, window_to}) do
    Register.list_acts_published_between(window_from, window_to, limit: @digest_limit)
  end

  def matches(%Subscription{query: query}, {window_from, window_to}) do
    Search.window_matches(query, from: window_from, to: window_to, limit: @query_limit)
  end

  @doc "How many acts a digest email lists before it starts saying 'and more'."
  def digest_limit, do: @digest_limit
end
