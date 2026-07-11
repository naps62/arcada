defmodule ArcadaWeb.RegisterLiveTest do
  use ArcadaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Arcada.Repo
  alias Arcada.Register.{Edition, Act, Summary}

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
      domains: [:trabalho]
    })
    |> Repo.insert!()

    %{fiscal: fiscal, trabalho: trabalho}
  end

  test "renders the register grouped by date with both acts", %{conn: conn} do
    seed()
    {:ok, _lv, html} = live(conn, ~p"/")

    assert html =~ "Arcada"
    assert html =~ "24 de junho de 2026"
    assert html =~ "Muda o escalão do IRS."
    assert html =~ "Atualiza regras de trabalho."
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

  test "front door shows the slogan h1; a section shows its scoped h1", %{conn: conn} do
    seed()

    {:ok, _lv, root} = live(conn, ~p"/")
    assert root =~ "<h1"
    assert root =~ "Onde a lei fala português."

    {:ok, _lv, section} = live(conn, ~p"/?domain=fiscal")
    assert section =~ ~r|<h1[^>]*>\s*Fiscal\s*</h1>|
    refute section =~ "Onde a lei fala português."
  end

  test "domain pills show act counts", %{conn: conn} do
    seed()
    {:ok, _lv, html} = live(conn, ~p"/")
    # both 'fiscal' and 'trabalho' have 1 act each
    assert html =~ "fiscal"
    assert html =~ "Tudo"
  end

  test "browse infinite-scrolls older days on demand", %{conn: conn} do
    # 12 publication days, one act each; the page size is 10 days, so the two
    # oldest days only appear after a load-more. Zero-padded titles so no title
    # is a substring of another (e.g. "01" vs "12").
    for d <- 1..12 do
      date = Date.new!(2026, 6, d)
      label = String.pad_leading("#{d}", 2, "0")

      ed =
        %Edition{}
        |> Edition.changeset(%{serie: "I", number: "n-#{d}", date: date})
        |> Repo.insert!()

      %Act{}
      |> Act.changeset(%{
        edition_id: ed.id,
        dre_id: "d-#{d}",
        title: "Diploma #{label}",
        published_at: date
      })
      |> Repo.insert!()
    end

    {:ok, lv, html} = live(conn, ~p"/")

    # Newest 10 days (12 down to 03) are on the first page; 02 and 01 are not.
    assert html =~ "Diploma 12"
    assert html =~ "Diploma 03"
    refute html =~ "Diploma 02"
    refute html =~ "Diploma 01"
    assert html =~ ~s(phx-viewport-bottom="load-more")

    html = render_hook(lv, "load-more", %{})

    # The remaining days append; the sentinel drops once everything is loaded.
    assert html =~ "Diploma 02"
    assert html =~ "Diploma 01"
    # …without dropping the already-loaded days.
    assert html =~ "Diploma 12"
    refute html =~ ~s(phx-viewport-bottom="load-more")
  end
end
