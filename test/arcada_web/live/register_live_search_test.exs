defmodule ArcadaWeb.RegisterLiveSearchTest do
  @moduledoc """
  The semantic search box lives on the register front page itself (issue #27),
  above the domain/period filters — not a separate page. `async: false`: search
  goes through the process-wide `Arcada.Search.Index` singleton.
  """
  use ArcadaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Arcada.Register.{Act, Edition, Summary}
  alias Arcada.Repo
  alias Arcada.Search.Index
  alias Arcada.Summarizer.Embeddings

  setup do
    Index.clear()
    :ok
  end

  defp set_embeddings(kw) do
    prev = Application.get_env(:arcada, Embeddings, [])
    Application.put_env(:arcada, Embeddings, kw)
    on_exit(fn -> Application.put_env(:arcada, Embeddings, prev) end)
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

  # A distinctly-titled indexed act, so a page's contents are identifiable in the
  # rendered HTML. All share the same vector → all match, ranked by insertion.
  defp seed_titled_act(title, n) do
    ed =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "p-#{n}/2026", date: ~D[2026-06-24]})
      |> Repo.insert!()

    act =
      %Act{}
      |> Act.changeset(%{edition_id: ed.id, dre_id: "page-#{n}", title: title})
      |> Repo.insert!()

    summary =
      %Summary{}
      |> Summary.changeset(%{act_id: act.id, plain_text: title, embedding: [1.0, 0.0]})
      |> Repo.insert!()

    Index.put(summary.id, act.id, [1.0, 0.0])
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

  test "caps the first page at 20 results and offers more via infinite scroll", %{conn: conn} do
    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)
    for n <- 1..25, do: seed_titled_act("Diploma número #{n}", n)

    # Unique query: the Index query→embedding cache is a process-wide singleton
    # that outlives the test, so reusing a query across tests hits a stale entry.
    {:ok, lv, _html} = live(conn, ~p"/?#{[q: "scroll-infinito-primeira-pagina"]}")
    html = render(lv)

    assert results_count(html) == 20
    # More to come → the list carries the viewport binding that fires load-more.
    assert html =~ ~s(phx-viewport-bottom="load-more")
  end

  test "load-more appends the next window without re-embedding or re-flashing", %{conn: conn} do
    parent = self()

    set_embeddings(
      embed_fn: fn texts ->
        send(parent, :embedded)
        {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)}
      end
    )

    for n <- 1..25, do: seed_titled_act("Diploma número #{n}", n)

    # Unique query (see note above): a reused query would be served from the
    # Index cache, so `embed_fn` — and the :embedded probe — would never fire.
    {:ok, lv, _html} = live(conn, ~p"/?#{[q: "scroll-infinito-carrega-mais"]}")
    first = render(lv)
    assert_received :embedded

    html = render_hook(lv, "load-more", %{})

    # All 25 now loaded; the binding is dropped so scrolling stops firing.
    assert results_count(html) == 25
    refute html =~ ~s(phx-viewport-bottom="load-more")
    # Paging must reuse the cached ranking — no second embed call.
    refute_received :embedded
    # Appending a page must not re-flash the whole container (token unchanged).
    assert token(first) == token(html)
  end

  test "load-more is a no-op in browse mode (no cached ranking)", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")
    # Should not crash even though there's no search in progress.
    assert render_hook(lv, "load-more", %{}) =~ "search-form"
  end

  defp results_count(html) do
    Regex.scan(~r/id="search-result-\d+"/, html) |> length()
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

  # --- Rate limiting (issue #32) ------------------------------------------------

  alias Arcada.Accounts.User

  # Force the semantic-search rate limits for the duration of a test, restoring
  # them afterwards. `per_minute: 0` denies the very first query.
  defp set_rate_limits(kw) do
    prev = Application.get_env(:arcada, Arcada.RateLimit, [])
    Application.put_env(:arcada, Arcada.RateLimit, kw)
    on_exit(fn -> Application.put_env(:arcada, Arcada.RateLimit, prev) end)
  end

  # An act whose summary body FTS can match on `term`, so a rate-limited
  # (semantic-off) search still surfaces it.
  defp seed_fts_act(term) do
    ed =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "rl-1/2026", date: ~D[2026-06-24]})
      |> Repo.insert!()

    act =
      %Act{}
      |> Act.changeset(%{edition_id: ed.id, dre_id: "rl-1", title: "Lei do #{term}"})
      |> Repo.insert!()

    %Summary{}
    |> Summary.changeset(%{act_id: act.id, plain_text: "novo apoio ao #{term} jovem"})
    |> Repo.insert!()

    act
  end

  test "over the anon limit, search degrades to FTS-only with a sign-up nudge", %{conn: conn} do
    set_rate_limits(anon: [per_minute: 0, per_day: 0])
    # Semantic must not even be attempted when degraded.
    set_embeddings(embed_fn: fn _ -> raise "should not embed when rate-limited" end)
    seed_fts_act("arrendamento")

    {:ok, _lv, html} = live(conn, ~p"/?#{[q: "arrendamento"]}")

    # The nudge appears with sign-in + register calls to action…
    assert html =~ "resultados por texto"
    assert html =~ "cria conta"
    assert html =~ ~p"/users/register"
    # …and FTS still returned the act, so search stayed useful.
    assert html =~ "Lei do arrendamento"
  end

  test "under the limit there is no degraded banner", %{conn: conn} do
    seed_indexed_act([1.0, 0.0])
    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

    {:ok, lv, _html} = live(conn, ~p"/")
    html = lv |> form("#search-form", %{"q" => "sem limite atingido"}) |> render_change()

    refute html =~ "resultados por texto"
    refute html =~ "cria conta"
  end

  test "a verified user over their limit sees a slow-down message, not a sign-up nudge",
       %{conn: conn} do
    user =
      Arcada.AccountsFixtures.user_fixture()
      |> User.confirm_changeset()
      |> Arcada.Repo.update!()

    conn = log_in_user(conn, user)

    set_rate_limits(user: [per_minute: 0, per_day: 0])
    set_embeddings(embed_fn: fn _ -> raise "should not embed when rate-limited" end)
    seed_fts_act("arrendamento")

    {:ok, _lv, html} = live(conn, ~p"/?#{[q: "arrendamento"]}")

    assert html =~ "depressa demais"
    refute html =~ "cria conta"
    assert html =~ "Lei do arrendamento"
  end
end
