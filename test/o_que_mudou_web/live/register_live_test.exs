defmodule OQueMudouWeb.RegisterLiveTest do
  use OQueMudouWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias OQueMudou.Repo
  alias OQueMudou.Register.{Edition, Act, Summary}

  defp seed do
    ed =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "120/2026", date: ~D[2026-06-24]})
      |> Repo.insert!()

    fiscal =
      %Act{}
      |> Act.changeset(%{
        edition_id: ed.id,
        dre_id: "1",
        title: "Decreto-Lei do IRS",
        emitter: "Finanças",
        published_at: ~D[2026-06-24]
      })
      |> Repo.insert!()

    %Summary{}
    |> Summary.changeset(%{
      act_id: fiscal.id,
      plain_text: "Muda o escalão do IRS.",
      domains: [:fiscal]
    })
    |> Repo.insert!()

    trabalho =
      %Act{}
      |> Act.changeset(%{
        edition_id: ed.id,
        dre_id: "2",
        title: "Portaria laboral",
        published_at: ~D[2026-06-24]
      })
      |> Repo.insert!()

    %Summary{}
    |> Summary.changeset(%{
      act_id: trabalho.id,
      plain_text: "Atualiza regras de trabalho.",
      domains: [:trabalho],
      validated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!()

    %{fiscal: fiscal, trabalho: trabalho}
  end

  test "renders the register grouped by date with both acts", %{conn: conn} do
    seed()
    {:ok, _lv, html} = live(conn, ~p"/")

    assert html =~ "O que mudou"
    assert html =~ "24 de junho de 2026"
    assert html =~ "Muda o escalão do IRS."
    assert html =~ "Atualiza regras de trabalho."
  end

  test "surfaces unreviewed vs validated state", %{conn: conn} do
    seed()
    {:ok, _lv, html} = live(conn, ~p"/")

    assert html =~ "não revisto"
    assert html =~ "verificado"
  end

  test "domain filter narrows the list", %{conn: conn} do
    seed()
    {:ok, lv, _html} = live(conn, ~p"/")

    html = lv |> element("a", "fiscal") |> render_click()

    assert html =~ "Muda o escalão do IRS."
    refute html =~ "Atualiza regras de trabalho."
  end

  test "empty state when no acts match", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/?domain=saúde")
    assert html =~ "Nada a mostrar"
  end

  test "domain pills show act counts", %{conn: conn} do
    seed()
    {:ok, _lv, html} = live(conn, ~p"/")
    # both 'fiscal' and 'trabalho' have 1 act each
    assert html =~ "fiscal"
    assert html =~ "Tudo"
  end
end
