defmodule ArcadaWeb.ActRedirectController do
  @moduledoc """
  301s the bare `/acts/:dre_id` to the canonical `/acts/:dre_id/:slug`.

  Keeps a single indexable URL per act: crawlers hitting the slugless form get a
  real HTTP 301 to the slugged canonical instead of a soft LiveView client nav.
  Unknown `dre_id` raises `Ecto.NoResultsError` → 404.
  """
  use ArcadaWeb, :controller

  alias Arcada.Register
  alias ArcadaWeb.SEO

  def show(conn, %{"dre_id" => dre_id}) do
    act = Register.get_act_by_dre_id!(dre_id)

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: SEO.act_path(act))
  end
end
