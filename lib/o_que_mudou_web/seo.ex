defmodule OQueMudouWeb.SEO do
  @moduledoc """
  Small helpers for the SEO baseline: canonical URLs and the `robots` meta value.
  See issue #36.

  The site is always indexable at the app layer — reachability is gated at the
  edge (Cloudflare firewall) until go-live, so there's no need for a second
  in-app noindex switch. Individual pages can still opt out with
  `robots_meta(page_noindex: true)` (e.g. search results).
  """

  alias OQueMudouWeb.Endpoint

  @default_description "O Diário da República, Série I, em linguagem simples: o que muda, para quem, e a partir de quando — sempre com a fonte oficial ao lado."

  @doc "The site's default meta description (Portuguese)."
  def default_description, do: @default_description

  @doc "Absolute URL for `path` (e.g. `/acts/12`), rooted at the endpoint host."
  def url(path), do: Endpoint.url() <> path

  @doc """
  The `robots` meta content for a page. Indexable by default; a page opts out of
  indexing (but not link-following) by passing `page_noindex: true`.
  """
  def robots_meta(page_noindex \\ false)
  def robots_meta(true), do: "noindex, follow"
  def robots_meta(_), do: "index, follow"
end
