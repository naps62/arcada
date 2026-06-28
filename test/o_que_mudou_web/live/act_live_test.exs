defmodule OQueMudouWeb.ActLiveTest do
  use OQueMudouWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias OQueMudou.Repo
  alias OQueMudou.Register
  alias OQueMudou.Register.{Edition, Act, Summary}

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
    {:ok, lv, html} = live(conn, ~p"/acts/#{act.id}")

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

  test "mark-validated toggle persists validated_at", %{conn: conn} do
    %{act: act, summary: summary} = seed()
    {:ok, lv, html} = live(conn, ~p"/acts/#{act.id}")

    assert html =~ "Marcar como validado"
    assert is_nil(Repo.get!(Summary, summary.id).validated_at)

    after_click = lv |> element("button", "Marcar como validado") |> render_click()
    assert after_click =~ "verificado"
    refute is_nil(Repo.get!(Summary, summary.id).validated_at)

    # toggling again clears it
    lv |> element("button", "Validado") |> render_click()
    assert is_nil(Repo.get!(Summary, summary.id).validated_at)
  end

  test "unknown act id raises (404)", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/acts/999999") end
  end

  describe "Register.set_validated/2" do
    test "stamps and clears validated_at" do
      %{summary: summary} = seed()
      assert {:ok, v} = Register.set_validated(summary, true)
      assert v.validated_at
      assert {:ok, cleared} = Register.set_validated(v, false)
      assert is_nil(cleared.validated_at)
    end
  end
end
