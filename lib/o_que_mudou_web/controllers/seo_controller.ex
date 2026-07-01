defmodule OQueMudouWeb.SeoController do
  @moduledoc """
  Dynamically-served `robots.txt` and `sitemap.xml`.

  Both are dynamic (not static files) so they track the SEO indexing gate: while
  the site is not indexable (`OQueMudouWeb.SEO.indexable?/0` — off until go-live)
  `robots.txt` disallows the whole site. `/admin*` is always disallowed. The
  sitemap lists the public section pages plus every act with a published summary.
  See issue #36.
  """
  use OQueMudouWeb, :controller

  alias OQueMudou.Register
  alias OQueMudouWeb.SEO

  # Domains that get their own browse/section URL in the sitemap.
  @section_domains Register.life_domains()

  def robots(conn, _params) do
    body =
      if SEO.indexable?() do
        """
        User-agent: *
        Disallow: /admin
        Disallow: /users
        Disallow: /dev

        Sitemap: #{SEO.url(~p"/sitemap.xml")}
        """
      else
        # Pre-launch: keep the whole site out of crawlers.
        """
        User-agent: *
        Disallow: /
        """
      end

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  def sitemap(conn, _params) do
    urls =
      static_urls() ++ section_urls() ++ act_urls()

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

  defp static_urls do
    [
      %{loc: SEO.url(~p"/"), changefreq: "daily", priority: "1.0"},
      %{loc: SEO.url(~p"/faq"), changefreq: "monthly", priority: "0.3"},
      %{loc: SEO.url(~p"/sobre"), changefreq: "monthly", priority: "0.3"}
    ]
  end

  defp section_urls do
    Enum.map(@section_domains, fn domain ->
      %{loc: SEO.url(~p"/?#{[domain: domain]}"), changefreq: "daily", priority: "0.5"}
    end)
  end

  defp act_urls do
    Enum.map(Register.sitemap_acts(), fn {id, updated_at} ->
      %{
        loc: SEO.url(~p"/acts/#{id}"),
        lastmod: updated_at && DateTime.to_iso8601(updated_at),
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
