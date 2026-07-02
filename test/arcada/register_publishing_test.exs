defmodule Arcada.RegisterPublishingTest do
  use Arcada.DataCase, async: true

  alias Arcada.Register
  alias Arcada.Register.{Edition, Act, Summary}

  defp setup_act do
    edition =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "1/2026", date: ~D[2026-06-24]})
      |> Repo.insert!()

    act = %Act{} |> Act.changeset(%{edition_id: edition.id, dre_id: "1"}) |> Repo.insert!()

    older =
      %Summary{}
      |> Summary.changeset(%{
        act_id: act.id,
        plain_text: "older",
        generated_at: ~U[2026-06-24 09:00:00Z]
      })
      |> Repo.insert!()

    newer =
      %Summary{}
      |> Summary.changeset(%{
        act_id: act.id,
        plain_text: "newer",
        generated_at: ~U[2026-06-24 10:00:00Z]
      })
      |> Repo.insert!()

    {Register.get_act!(act.id), older, newer}
  end

  test "published_summary defaults to the latest, then honors the published pick" do
    {act, older, _newer} = setup_act()
    assert Register.published_summary(act).plain_text == "newer"

    {:ok, _} = Register.set_published(act, older)

    assert Register.get_act!(act.id) |> Register.published_summary() |> Map.get(:plain_text) ==
             "older"
  end

  test "clearing the published summary falls back to the latest" do
    {act, older, _newer} = setup_act()
    {:ok, _} = Register.set_published(act, older)
    {:ok, _} = Register.set_published(Register.get_act!(act.id), nil)

    assert Register.get_act!(act.id) |> Register.published_summary() |> Map.get(:plain_text) ==
             "newer"
  end
end
