defmodule OQueMudouWeb.SearchLiveTest do
  use OQueMudouWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias OQueMudou.Register.{Act, Edition, Summary}
  alias OQueMudou.Repo
  alias OQueMudou.Search.Index
  alias OQueMudou.Summarizer.Embeddings

  setup do
    Index.clear()
    :ok
  end

  defp set_embeddings(kw) do
    prev = Application.get_env(:o_que_mudou, Embeddings, [])
    Application.put_env(:o_que_mudou, Embeddings, kw)
    on_exit(fn -> Application.put_env(:o_que_mudou, Embeddings, prev) end)
  end

  defp seed_indexed_act(vector) do
    ed =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "9/2026", date: ~D[2026-06-24]})
      |> Repo.insert!()

    act =
      %Act{}
      |> Act.changeset(%{edition_id: ed.id, dre_id: "search-1", title: "Decreto-Lei do IRS"})
      |> Repo.insert!()

    summary =
      %Summary{}
      |> Summary.changeset(%{
        act_id: act.id,
        plain_text: "Muda o escalão do IRS.",
        embedding: vector
      })
      |> Repo.insert!()

    Index.put(summary.id, act.id, vector)
    act
  end

  test "renders the empty search box with no results yet", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/pesquisar")
    assert html =~ "Pesquisar"
    refute html =~ "Nada encontrado"
  end

  test "typing a query returns semantically-ranked acts", %{conn: conn} do
    seed_indexed_act([1.0, 0.0])
    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

    {:ok, lv, _html} = live(conn, ~p"/pesquisar")
    html = lv |> form("form", %{"q" => "apoio ao arrendamento"}) |> render_change()

    assert html =~ "Muda o escalão do IRS."
  end

  test "an unmatched query shows the empty state", %{conn: conn} do
    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

    {:ok, lv, _html} = live(conn, ~p"/pesquisar")
    html = lv |> form("form", %{"q" => "algo sem resultados"}) |> render_change()

    assert html =~ "Nada encontrado"
  end

  test "never crashes when the embeddings server is disabled", %{conn: conn} do
    set_embeddings([])

    {:ok, lv, _html} = live(conn, ~p"/pesquisar")
    html = lv |> form("form", %{"q" => "qualquer coisa"}) |> render_change()

    assert html =~ "Nada encontrado"
  end
end
