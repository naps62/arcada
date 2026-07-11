defmodule ArcadaWeb.OgImageController do
  @moduledoc """
  Serves the per-act social share card (`/acts/:dre_id/og.png`) referenced by
  each act page's `og:image`. Rendered on demand by `Arcada.OgImage`; a long
  `Cache-Control` lets Cloudflare hold it at the edge. If rasterisation is
  unavailable (rsvg missing / failure), falls back to the static default card.
  """
  use ArcadaWeb, :controller

  alias Arcada.{OgImage, Register}

  def show(conn, %{"dre_id" => dre_id}) do
    act = Register.get_act_by_dre_id!(dre_id)

    case OgImage.png(act) do
      {:ok, png} ->
        conn
        |> put_resp_content_type("image/png")
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> send_resp(200, png)

      {:error, _reason} ->
        redirect(conn, to: ~p"/images/og-default.png")
    end
  end
end
