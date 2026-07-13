defmodule ArcadaWeb.SeoControllerTest do
  use ArcadaWeb.ConnCase, async: false

  alias Arcada.Repo
  alias Arcada.Register.{Edition, Act, Summary}

  defp seed_published_act do
    ed =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "120/2026", date: ~D[2026-06-24]})
      |> Repo.insert!()

    act =
      %Act{}
      |> Act.changeset(%{edition_id: ed.id, dre_id: "84", title: "Decreto n.º 84/2026"})
      |> Repo.insert!()

    summary =
      %Summary{}
      |> Summary.changeset(%{act_id: act.id, plain_text: "Muda X."})
      |> Repo.insert!()

    {:ok, act} = Arcada.Register.set_published(act, summary)
    act
  end

  defp seed_feed_act(dre_id, opts) do
    ed =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "#{dre_id}/2026", date: ~D[2026-06-24]})
      |> Repo.insert!()

    act =
      %Act{}
      |> Act.changeset(%{
        edition_id: ed.id,
        dre_id: dre_id,
        title: "Decreto n.º #{dre_id}",
        published_at: ~D[2026-06-24],
        source_url: "https://diariodarepublica.pt/#{dre_id}"
      })
      |> Repo.insert!()

    summary =
      %Summary{}
      |> Summary.changeset(%{
        act_id: act.id,
        plain_text: opts[:plain_text] || "Muda X.",
        headline: opts[:headline],
        domains: opts[:domains] || []
      })
      |> Repo.insert!()

    {:ok, act} = Arcada.Register.set_published(act, summary)
    act
  end

  describe "robots.txt" do
    test "allows crawling but guards /admin, /users, /dev", %{conn: conn} do
      resp = get(conn, ~p"/robots.txt")
      body = response(resp, 200)

      assert response_content_type(resp, :txt) =~ "text/plain"
      assert body =~ "User-agent: *"
      assert body =~ "Disallow: /admin"
      assert body =~ "Disallow: /users"
      assert body =~ "Disallow: /dev"
      assert body =~ "Sitemap: http"
      assert body =~ "/sitemap.xml"
    end
  end

  describe "sitemap.xml" do
    test "lists section pages and published acts", %{conn: conn} do
      act = seed_published_act()
      resp = get(conn, ~p"/sitemap.xml")
      body = response(resp, 200)

      assert response_content_type(resp, :xml) =~ "xml"
      assert body =~ "<urlset"
      assert body =~ "/faq</loc>" or body =~ "/faq<"
      assert body =~ "/sobre"
      assert body =~ "domain=fiscal"
      assert body =~ "/acts/#{act.dre_id}/#{Act.slug(act)}</loc>"
      # root + sections carry a lastmod hint (newest act timestamp)
      assert body =~ "<lastmod>"
    end

    test "omits acts without a published summary", %{conn: conn} do
      ed =
        %Edition{}
        |> Edition.changeset(%{serie: "I", number: "999/2026", date: ~D[2026-06-24]})
        |> Repo.insert!()

      act =
        %Act{}
        |> Act.changeset(%{edition_id: ed.id, dre_id: "stub", title: "Sem resumo"})
        |> Repo.insert!()

      body = conn |> get(~p"/sitemap.xml") |> response(200)
      refute body =~ "/acts/#{act.dre_id}/#{Act.slug(act)}</loc>"
    end
  end

  describe "rss.xml" do
    test "emits an RSS 2.0 item per published act, terms stripped", %{conn: conn} do
      act =
        seed_feed_act("rss1",
          headline: "Corte no [[IVA]] da energia",
          plain_text: "Baixa o [[IVA]] da luz & do gás.",
          domains: [:fiscal]
        )

      resp = get(conn, ~p"/rss.xml")
      body = response(resp, 200)

      assert [ctype] = get_resp_header(resp, "content-type")
      assert ctype =~ "application/rss+xml"
      assert get_resp_header(resp, "cache-control") == ["public, max-age=1800"]
      assert body =~ ~s(<rss version="2.0")
      # [[term]] markers stripped from the visible title
      assert body =~ "<title>Corte no IVA da energia</title>"
      refute body =~ "[[IVA]]"
      # body wrapped in CDATA so raw & / < survive
      assert body =~ "<![CDATA[Baixa o IVA da luz & do gás.]]>"
      assert body =~ "<category>fiscal</category>"
      assert body =~ "/acts/#{act.dre_id}/#{Act.slug(act)}"
      assert body =~ "<pubDate>"
    end

    test "?domain= filters to that life-domain", %{conn: conn} do
      fiscal = seed_feed_act("rssf", domains: [:fiscal], headline: "Fiscal")
      trabalho = seed_feed_act("rsst", domains: [:trabalho], headline: "Trabalho")

      body = conn |> get(~p"/rss.xml?#{[domain: "fiscal"]}") |> response(200)

      assert body =~ "Arcada — Fiscal"
      assert body =~ "/acts/#{fiscal.dre_id}/"
      refute body =~ "/acts/#{trabalho.dre_id}/"
    end

    test "unknown ?domain= falls back to the global feed", %{conn: conn} do
      act = seed_feed_act("rssg", domains: [:fiscal], headline: "Global")

      body = conn |> get(~p"/rss.xml?#{[domain: "nope"]}") |> response(200)

      assert body =~ "<title>Arcada</title>"
      assert body =~ "/acts/#{act.dre_id}/"
    end
  end
end
