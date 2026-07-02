defmodule ArcadaWeb.SEO do
  @moduledoc """
  The site's SEO surface: page metadata (title, description, canonical, JSON-LD)
  plus the canonical-URL and `robots` baseline. See issues #36 and #51.

  `metadata_for/1` builds the per-page metadata each public LiveView assigns —
  the branch-heavy logic (filtered vs unfiltered canonical, WebSite+SearchAction
  vs Article JSON-LD) lives here, directly testable, instead of buried as private
  helpers inside the views.

  The site is always indexable at the app layer — reachability is gated at the
  edge (Cloudflare firewall) until go-live, so there's no need for a second
  in-app noindex switch. Individual pages can still opt out with
  `robots_meta(page_noindex: true)` (e.g. search results).
  """

  use ArcadaWeb, :verified_routes
  # Keep the `~p` sigil but drop Phoenix's `url/1` — this module exposes its own
  # `url/1` (a plain host + path concat) as the site-wide absolute-URL helper.
  import Phoenix.VerifiedRoutes, except: [url: 1]

  alias Arcada.Register
  alias Arcada.Register.Summary
  alias ArcadaWeb.Endpoint

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

  @doc """
  Page metadata for a public view, as a map ready to `assign` — `page_title`,
  `page_description`, `canonical_url`, `page_noindex`, `json_ld` (and `og_type`
  for articles). The caller assigns it wholesale; the root layout falls back to
  the defaults for any key a page leaves unset.

  Shapes:

    * `:home` / `{:browse, domain, period}` — the register listing (`domain`,
      `period` may be `nil` for the unfiltered front door).
    * `{:search, query}` — a search-result page (noindex, canonicalised to `/`).
    * `{:act, act, summary}` — an act detail page (`summary` may be `nil`).
  """
  def metadata_for(:home), do: metadata_for({:browse, nil, nil})

  def metadata_for({:browse, domain, period}) do
    %{
      page_title: browse_title(domain, period),
      page_description: browse_description(domain, period),
      canonical_url: browse_canonical(domain, period),
      page_noindex: false,
      json_ld: browse_json_ld(domain, period)
    }
  end

  def metadata_for({:search, query}) do
    %{
      page_title: "Pesquisa: #{query}",
      page_description: @default_description,
      # Search-result pages carry a query string and thin, shifting content —
      # keep them out of the index, canonicalise to the register root.
      page_noindex: true,
      canonical_url: url(~p"/"),
      json_ld: nil
    }
  end

  def metadata_for({:act, act, summary}) do
    title = act_title(act, summary)
    description = act_description(act, summary)
    canonical = url(~p"/acts/#{act.id}")

    %{
      page_title: title,
      page_description: description,
      canonical_url: canonical,
      og_type: "article",
      json_ld: article_json_ld(act, title, description, canonical)
    }
  end

  # --- Browse / home ---------------------------------------------------------

  # nil title → the layout renders the bare "Arcada" masthead (no scope prefix).
  defp browse_title(nil, nil), do: nil
  defp browse_title(domain, nil), do: to_string(domain)
  defp browse_title(nil, period), do: Register.period_label(period)
  defp browse_title(domain, period), do: "#{domain} · #{Register.period_label(period)}"

  defp browse_description(nil, nil), do: @default_description

  defp browse_description(domain, period) do
    scope = browse_title(domain, period)

    "Atos do Diário da República, Série I — #{scope} — em linguagem simples, com a fonte oficial ao lado."
  end

  # Canonical for a filtered browse view preserves the active domain/period so
  # each section page is its own canonical; the unfiltered root canonicalises to /.
  defp browse_canonical(nil, nil), do: url(~p"/")

  defp browse_canonical(domain, period) do
    params =
      [domain: domain, period: period && to_string(period)]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    url(~p"/?#{params}")
  end

  # The register root is the site's front door: describe the whole product and
  # advertise the on-site search (WebSite + SearchAction) for rich results. On a
  # filtered view we drop the SearchAction and just describe the slice.
  defp browse_json_ld(nil, nil) do
    %{
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "name" => "Arcada",
      "url" => url(~p"/"),
      "inLanguage" => "pt-PT",
      "description" => @default_description,
      "potentialAction" => %{
        "@type" => "SearchAction",
        "target" => %{
          "@type" => "EntryPoint",
          "urlTemplate" => url(~p"/") <> "?q={search_term_string}"
        },
        "query-input" => "required name=search_term_string"
      }
    }
  end

  defp browse_json_ld(_domain, _period), do: nil

  # --- Act -------------------------------------------------------------------

  defp act_title(act, summary) do
    (summary && Summary.strip_terms(summary.headline)) || act.title || act.tipo || "Ato"
  end

  # Meta description: the summary in plain language, trimmed to a sane length;
  # falls back to the act's formal title when there's no summary yet.
  defp act_description(_act, %{plain_text: text}) when is_binary(text),
    do: truncate(Summary.strip_terms(text), 300)

  defp act_description(%{title: title}, _summary) when is_binary(title), do: truncate(title, 300)
  defp act_description(_act, _summary), do: @default_description

  defp truncate(text, max) do
    text = text |> String.replace(~r/\s+/, " ") |> String.trim()
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
  end

  defp article_json_ld(act, title, description, canonical) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Article",
      "headline" => title,
      "description" => description,
      "inLanguage" => "pt-PT",
      "isAccessibleForFree" => true,
      "mainEntityOfPage" => canonical,
      "publisher" => %{"@type" => "Organization", "name" => "Arcada"}
    }
    |> maybe_put("datePublished", act.published_at && Date.to_iso8601(act.published_at))
    |> maybe_put("articleSection", act.tipo)
    |> maybe_put("isBasedOn", act.source_url)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
