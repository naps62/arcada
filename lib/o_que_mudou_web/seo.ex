defmodule OQueMudouWeb.SEO do
  @moduledoc """
  Small helpers for the SEO baseline: canonical URLs, the site-wide indexing
  gate, and the `robots` meta value. See issue #36.

  Indexing is **off by default**: until `:o_que_mudou, :seo, indexable: true`
  (set via `SEO_INDEXABLE=true` on go-live), every page ships `noindex` and
  `robots.txt` disallows the whole site. This keeps the pre-launch site out of
  search results even if it's briefly reachable.
  """

  alias OQueMudouWeb.Endpoint

  @default_description "O Diário da República, Série I, em linguagem simples: o que muda, para quem, e a partir de quando — sempre com a fonte oficial ao lado."

  @doc "The site's default meta description (Portuguese)."
  def default_description, do: @default_description

  @doc "Whether the site may be indexed. Defaults to false until go-live."
  def indexable?, do: Application.get_env(:o_que_mudou, :seo, [])[:indexable] == true

  @doc "Absolute URL for `path` (e.g. `/acts/12`), rooted at the endpoint host."
  def url(path), do: Endpoint.url() <> path

  @doc """
  The `robots` meta content for a page. The site-wide gate wins: while the site
  is not indexable everything is `noindex, nofollow`. Once live, a page may still
  opt out (search results, etc.) by passing `page_noindex: true`.
  """
  def robots_meta(page_noindex \\ false) do
    cond do
      not indexable?() -> "noindex, nofollow"
      page_noindex -> "noindex, follow"
      true -> "index, follow"
    end
  end
end
