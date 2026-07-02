defmodule OQueMudouWeb.AdminActsLiveTest do
  use OQueMudouWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias OQueMudou.Repo
  alias OQueMudou.Register
  alias OQueMudou.Register.{Edition, Act, Summary}

  defp edition(date) do
    %Edition{}
    |> Edition.changeset(%{
      serie: "I",
      number: "#{System.unique_integer([:positive])}/2026",
      date: date
    })
    |> Repo.insert!()
  end

  defp act(attrs) do
    ed = edition(attrs[:date] || ~D[2026-06-24])

    %Act{}
    |> Act.changeset(
      Map.merge(
        %{edition_id: ed.id, dre_id: "#{System.unique_integer([:positive])}"},
        Map.take(attrs, [:title, :tipo, :published_at])
      )
    )
    |> Repo.insert!()
  end

  defp summary(act, attrs) do
    %Summary{}
    |> Summary.changeset(Map.merge(%{act_id: act.id, plain_text: "..."}, attrs))
    |> Repo.insert!()
  end

  test "lists acts newest-first with summary counts", %{conn: conn} do
    a = act(%{title: "Older act", published_at: ~D[2026-06-01]})
    summary(a, %{plain_text: "s1", generated_at: ~U[2026-06-01 09:00:00Z]})
    _b = act(%{title: "Newer act", published_at: ~D[2026-06-20]})

    {:ok, _lv, html} = conn |> live(~p"/admin/acts")

    assert html =~ "Older act"
    assert html =~ "Newer act"
    # Newest published first.
    assert :binary.match(html, "Newer act") < :binary.match(html, "Older act")
    assert html =~ "1 summary"
    assert html =~ "no summary"
  end

  test "filters by period via the query string", %{conn: conn} do
    _recent = act(%{title: "Recent act", date: Date.utc_today(), published_at: Date.utc_today()})
    _old = act(%{title: "Ancient act", date: ~D[2000-01-01], published_at: ~D[2000-01-01]})

    {:ok, _lv, html} = conn |> live(~p"/admin/acts?period=semana")

    assert html =~ "Recent act"
    refute html =~ "Ancient act"
  end

  test "renders summaries side-by-side and makes one canonical", %{conn: conn} do
    a = act(%{title: "Comparable act"})

    older =
      summary(a, %{plain_text: "older text", generated_at: ~U[2026-06-24 09:00:00Z]})

    _newer =
      summary(a, %{plain_text: "newer text", generated_at: ~U[2026-06-24 10:00:00Z]})

    {:ok, lv, html} = conn |> live(~p"/admin/acts/#{a.id}")

    assert html =~ "older text"
    assert html =~ "newer text"
    assert html =~ "Make canonical"

    lv |> element("button[phx-value-id='#{older.id}']", "Make canonical") |> render_click()

    assert Register.get_act!(a.id).published_summary_id == older.id
  end
end
