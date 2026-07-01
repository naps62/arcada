defmodule OQueMudouWeb.RegisterLiveSearchTest do
  @moduledoc """
  The semantic search box lives on the register front page itself (issue #27),
  above the domain/period filters — not a separate page. `async: false`: search
  goes through the process-wide `OQueMudou.Search.Index` singleton.
  """
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

  test "renders the search box above the filters", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/")
    assert html =~ "search-form"
    assert html =~ "Descreve a mudança que procuras"
  end

  test "typing a query shows ranked results instead of the filters", %{conn: conn} do
    seed_indexed_act([1.0, 0.0])
    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

    {:ok, lv, _html} = live(conn, ~p"/")
    html = lv |> form("#search-form", %{"q" => "apoio ao arrendamento"}) |> render_change()

    assert html =~ "Muda o escalão do IRS."
    refute html =~ "Filtros"
  end

  test "typing pushes the query into the URL so it's shareable", %{conn: conn} do
    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

    {:ok, lv, _html} = live(conn, ~p"/")
    lv |> form("#search-form", %{"q" => "arrendamento jovem"}) |> render_change()

    assert_patched(lv, ~p"/?#{[q: "arrendamento jovem"]}")
  end

  test "a shared ?q= link runs the search on load", %{conn: conn} do
    seed_indexed_act([1.0, 0.0])
    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

    {:ok, _lv, html} = live(conn, ~p"/?#{[q: "arrendamento"]}")

    assert html =~ "Muda o escalão do IRS."
    refute html =~ "Filtros"
    # The field is pre-filled from the URL so the shared link is self-explanatory.
    assert html =~ ~s(value="arrendamento")
    # Search results aren't grouped under a date header, so each carries its own.
    assert html =~ "24 de junho de 2026"
  end

  test "each new search re-flashes the results even when they're identical", %{conn: conn} do
    seed_indexed_act([1.0, 0.0])
    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

    {:ok, lv, _html} = live(conn, ~p"/")

    html1 = lv |> form("#search-form", %{"q" => "arrendamento"}) |> render_change()
    html2 = lv |> form("#search-form", %{"q" => "arrendament"}) |> render_change()

    # The FlashOnResult hook keys off data-token; it must change between searches
    # so an identical result set still visibly refreshes.
    assert token(html1) != token(html2)
    assert html1 =~ ~s(phx-hook="FlashOnResult")
  end

  defp token(html) do
    [_, tok] = Regex.run(~r/id="search-results"[^>]*data-token="(\d+)"/, html)
    tok
  end

  test "an unmatched query shows the empty state", %{conn: conn} do
    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

    {:ok, lv, _html} = live(conn, ~p"/")
    html = lv |> form("#search-form", %{"q" => "algo sem resultados"}) |> render_change()

    assert html =~ "Nada encontrado"
  end

  test "clearing the query restores the normal filtered listing", %{conn: conn} do
    seed_indexed_act([1.0, 0.0])
    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

    {:ok, lv, _html} = live(conn, ~p"/")
    lv |> form("#search-form", %{"q" => "algo"}) |> render_change()
    html = lv |> form("#search-form", %{"q" => ""}) |> render_change()

    assert html =~ "Filtros" or html =~ "Quando"
  end

  test "never crashes when the embeddings server is disabled", %{conn: conn} do
    set_embeddings([])

    {:ok, lv, _html} = live(conn, ~p"/")
    html = lv |> form("#search-form", %{"q" => "qualquer coisa"}) |> render_change()

    assert html =~ "Nada encontrado"
  end
end
