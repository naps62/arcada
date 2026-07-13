defmodule ArcadaWeb.SeoController do
  @moduledoc """
  Dynamically-served `robots.txt`, `sitemap.xml`, and the `rss.xml` feed.

  Crawling is allowed except for `/admin`, `/users`, and `/dev`. The sitemap
  lists the public section pages plus every act with a published summary. The
  feed is the newest acts (global, or per life-domain via `?domain=`). All are
  dynamic (not static files) so URLs track the configured host. See #36.
  """
  use ArcadaWeb, :controller

  alias Arcada.Register
  alias Arcada.Register.Summary
  alias ArcadaWeb.SEO

  # Domains that get their own browse/section URL in the sitemap.
  @section_domains Register.life_domains()

  def robots(conn, _params) do
    body = """
    User-agent: *
    Disallow: /admin
    Disallow: /users
    Disallow: /dev

    Sitemap: #{SEO.url(~p"/sitemap.xml")}
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  def sitemap(conn, _params) do
    acts = Register.sitemap_acts()
    # Newest act timestamp — a lastmod hint for the register root + sections,
    # which are all views over the same act set.
    latest = latest_lastmod(acts)

    urls =
      static_urls(latest) ++ section_urls(latest) ++ act_urls(acts)

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{Enum.map_join(urls, "\n", &url_node/1)}
    </urlset>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, body)
  end

  @doc """
  RSS 2.0 feed of the latest acts. The global feed lives at `/rss.xml`; a
  per-topic feed is the same route with `?domain=fiscal` (topics are query-param
  views of `/`, so the feed mirrors them). Cached at the edge like the OG images,
  so a feed reader polling every few minutes costs the origin ~nothing.
  """
  def feed(conn, params) do
    domain =
      case Register.fetch_domain(params["domain"] || "") do
        {:ok, atom} -> Atom.to_string(atom)
        :error -> nil
      end

    acts = Register.feed_acts(domain: domain)

    title = if domain, do: "Arcada — #{SEO.section_heading(domain, nil)}", else: "Arcada"
    site_link = if domain, do: SEO.url(~p"/?#{[domain: domain]}"), else: SEO.url(~p"/")

    self_link =
      if domain, do: SEO.url(~p"/rss.xml?#{[domain: domain]}"), else: SEO.url(~p"/rss.xml")

    build_date = acts |> List.first() |> item_date()

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
    <channel>
    <title>#{escape(title)}</title>
    <link>#{escape(site_link)}</link>
    <description>#{escape(SEO.default_description())}</description>
    <language>pt-PT</language>
    <atom:link href="#{escape(self_link)}" rel="self" type="application/rss+xml" />
    #{build_date && "<lastBuildDate>#{build_date}</lastBuildDate>"}
    #{Enum.map_join(acts, "\n", &item_node/1)}
    </channel>
    </rss>
    """

    conn
    |> put_resp_content_type("application/rss+xml")
    |> put_resp_header("cache-control", "public, max-age=1800")
    |> send_resp(200, body)
  end

  defp item_node(act) do
    summary = Register.published_summary(act)
    url = SEO.act_url(act)
    title = Summary.strip_terms(summary && summary.headline) || act.title || act.tipo
    body = Summary.strip_terms(summary && summary.plain_text) || ""
    domains = (summary && summary.domains) || []
    pub_date = item_date(act)

    [
      "<item>",
      "<title>#{escape(title)}</title>",
      "<link>#{escape(url)}</link>",
      "<guid isPermaLink=\"true\">#{escape(url)}</guid>",
      pub_date && "<pubDate>#{pub_date}</pubDate>",
      "<description>#{cdata(body)}</description>",
      act.source_url && "<source url=\"#{escape(act.source_url)}\">Diário da República</source>",
      Enum.map_join(domains, "\n", &"<category>#{escape(to_string(&1))}</category>"),
      "</item>"
    ]
    |> Enum.reject(&(is_nil(&1) || &1 == ""))
    |> Enum.join("\n")
  end

  # RSS pubDate is RFC-822 (not the sitemap's ISO-8601). Acts carry a `:date`
  # (`published_at`, fallback edition date), so anchor at midnight GMT. The
  # default Calendar locale yields the English day/month names RFC-822 wants.
  defp item_date(nil), do: nil

  defp item_date(act) do
    case act.published_at || (act.edition && act.edition.date) do
      %Date{} = d -> Calendar.strftime(d, "%a, %d %b %Y 00:00:00 +0000")
      _ -> nil
    end
  end

  # Wrap free text in CDATA so `<`/`&`/quotes in a summary can't break the XML.
  # Guard the one sequence CDATA itself can't contain.
  defp cdata(text) do
    safe = String.replace(text, "]]>", "]]]]><![CDATA[>")
    "<![CDATA[#{safe}]]>"
  end

  defp static_urls(latest) do
    [
      %{loc: SEO.url(~p"/"), lastmod: latest, changefreq: "daily", priority: "1.0"},
      %{loc: SEO.url(~p"/faq"), changefreq: "monthly", priority: "0.3"},
      %{loc: SEO.url(~p"/sobre"), changefreq: "monthly", priority: "0.3"}
    ]
  end

  defp section_urls(latest) do
    Enum.map(@section_domains, fn domain ->
      %{
        loc: SEO.url(~p"/?#{[domain: domain]}"),
        lastmod: latest,
        changefreq: "daily",
        priority: "0.5"
      }
    end)
  end

  defp latest_lastmod(acts) do
    acts
    |> Enum.map(& &1.updated_at)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      stamps -> stamps |> Enum.max(DateTime) |> DateTime.to_iso8601()
    end
  end

  defp act_urls(acts) do
    Enum.map(acts, fn act ->
      %{
        loc: SEO.act_url(act),
        lastmod: act.updated_at && DateTime.to_iso8601(act.updated_at),
        changefreq: "monthly",
        priority: "0.7"
      }
    end)
  end

  defp url_node(url) do
    [
      "  <url>",
      "    <loc>#{escape(url.loc)}</loc>",
      url[:lastmod] && "    <lastmod>#{url.lastmod}</lastmod>",
      url[:changefreq] && "    <changefreq>#{url.changefreq}</changefreq>",
      url[:priority] && "    <priority>#{url.priority}</priority>",
      "  </url>"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
