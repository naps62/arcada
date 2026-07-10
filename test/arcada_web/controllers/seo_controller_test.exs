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
end
