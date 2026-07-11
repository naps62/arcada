defmodule ArcadaWeb.OgImageControllerTest do
  use ArcadaWeb.ConnCase, async: true

  alias Arcada.Repo
  alias Arcada.Register.{Edition, Act, Summary}

  defp seed do
    ed =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "130/2026", date: ~D[2026-07-01]})
      |> Repo.insert!()

    act =
      %Act{}
      |> Act.changeset(%{
        edition_id: ed.id,
        dre_id: "913",
        tipo: "Portaria",
        title: "Portaria n.º 913/2026",
        published_at: ~D[2026-07-01]
      })
      |> Repo.insert!()

    %Summary{}
    |> Summary.changeset(%{
      act_id: act.id,
      plain_text: "Muda X.",
      headline: "Novas regras de apoio"
    })
    |> Repo.insert!()

    act
  end

  test "serves the share card (or falls back to the default card)", %{conn: conn} do
    act = seed()
    conn = get(conn, ~p"/acts/#{act.dre_id}/og.png")

    case conn.status do
      200 ->
        assert get_resp_header(conn, "content-type") |> hd() =~ "image/png"
        assert <<0x89, "PNG", _::binary>> = conn.resp_body

      302 ->
        # rsvg unavailable in this env — controller falls back to the static card.
        assert redirected_to(conn) == ~p"/images/og-default.png"
    end
  end

  test "404s for an unknown act", %{conn: conn} do
    assert_error_sent(404, fn -> get(conn, ~p"/acts/does-not-exist/og.png") end)
  end
end
