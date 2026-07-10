defmodule ArcadaWeb.ActLiveTest do
  use ArcadaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Arcada.Repo
  alias Arcada.Register.{Edition, Act, Summary}

  defp seed do
    ed =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "120/2026", date: ~D[2026-06-24]})
      |> Repo.insert!()

    act =
      %Act{}
      |> Act.changeset(%{
        edition_id: ed.id,
        dre_id: "84",
        tipo: "Decreto do Presidente da República",
        emitter: "Presidência da República",
        title: "Decreto n.º 84/2026",
        full_text: "<p>Texto integral do diploma.</p>",
        source_url: "https://diariodarepublica.pt/dr/detalhe/x",
        pdf_url: "https://files.diariodarepublica.pt/x.pdf",
        published_at: ~D[2026-06-24]
      })
      |> Repo.insert!()

    summary =
      %Summary{}
      |> Summary.changeset(%{
        act_id: act.id,
        plain_text: "Em linguagem simples: muda X.",
        domains: [:administração],
        model: "claude-sonnet-4-6",
        prompt_version: "v1"
      })
      |> Repo.insert!()

    %{act: act, summary: summary}
  end

  test "renders summary, sources and full-text toggle", %{conn: conn} do
    %{act: act} = seed()
    {:ok, lv, html} = live(conn, ~p"/acts/#{act.dre_id}/#{Act.slug(act)}")

    assert html =~ "Decreto n.º 84/2026"
    assert html =~ "Em linguagem simples: muda X."
    assert html =~ act.source_url
    assert html =~ act.pdf_url
    assert html =~ "administração"
    assert html =~ "claude-sonnet-4-6"

    # full text hidden until toggled
    refute html =~ "Texto integral do diploma"
    shown = lv |> element("button", "Ver texto integral") |> render_click()
    assert shown =~ "Texto integral do diploma"
  end

  test "sanitizes scraped full_text HTML before rendering (XSS)", %{conn: conn} do
    ed =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "121/2026", date: ~D[2026-06-25]})
      |> Repo.insert!()

    act =
      %Act{}
      |> Act.changeset(%{
        edition_id: ed.id,
        dre_id: "85",
        title: "Decreto n.º 85/2026",
        full_text: """
        <h2>Artigo 1.º</h2><p onclick="steal()">texto</p>\
        <table><tr><td>célula</td></tr></table>\
        <script>alert(document.cookie)</script><img src=x onerror=alert(1)>\
        """,
        source_url: "https://diariodarepublica.pt/dr/detalhe/y",
        published_at: ~D[2026-06-25]
      })
      |> Repo.insert!()

    {:ok, lv, _html} = live(conn, ~p"/acts/#{act.dre_id}/#{Act.slug(act)}")
    shown = lv |> element("button", "Ver texto integral") |> render_click()

    # legal formatting preserved
    assert shown =~ "Artigo 1.º"
    assert shown =~ "<table>"
    assert shown =~ "célula"
    # XSS vectors stripped
    refute shown =~ "<script"
    refute shown =~ "onclick"
    refute shown =~ "onerror"
  end

  test "unknown act dre_id raises (404)", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/acts/999999/x") end
  end

  test "bare /acts/:dre_id 301s to the canonical slug URL", %{conn: conn} do
    %{act: act} = seed()
    conn = get(conn, ~p"/acts/#{act.dre_id}")

    assert redirected_to(conn, 301) == "/acts/#{act.dre_id}/#{Act.slug(act)}"
  end

  test "emits per-act SEO: canonical, article OG, JSON-LD", %{conn: conn} do
    %{act: act} = seed()
    {:ok, _lv, html} = live(conn, ~p"/acts/#{act.dre_id}/#{Act.slug(act)}")

    assert html =~ ~s(rel="canonical")
    assert html =~ "/acts/#{act.dre_id}/#{Act.slug(act)}"
    assert html =~ ~s(property="og:type" content="article")
    assert html =~ ~s(name="description")
    assert html =~ "Em linguagem simples: muda X."
    assert html =~ "application/ld+json"
    assert html =~ ~s("@type":"Article")
  end
end
