defmodule Arcada.RegisterFixtures do
  @moduledoc """
  Test helpers for building editions, acts and summaries.
  """
  alias Arcada.Register.{Act, Edition, Summary}
  alias Arcada.Repo
  alias Arcada.Search.Index

  def edition_fixture(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    %Edition{}
    |> Edition.changeset(
      Enum.into(attrs, %{serie: "I", number: "s-#{n}/2026", date: ~D[2026-06-24]})
    )
    |> Repo.insert!()
  end

  @doc """
  An act, published on `:published_at` (defaults to its edition's date so the
  date-windowed queries have something to find).
  """
  def act_fixture(attrs \\ %{}) do
    n = System.unique_integer([:positive])
    attrs = Map.new(attrs)
    edition = Map.get_lazy(attrs, :edition, fn -> edition_fixture() end)

    %Act{}
    |> Act.changeset(
      attrs
      |> Map.drop([:edition])
      |> Enum.into(%{
        edition_id: edition.id,
        dre_id: "dre-#{n}",
        title: "Diploma #{n}",
        published_at: edition.date
      })
    )
    |> Repo.insert!()
  end

  @doc """
  A summary for `act`. Pass `:embedding` to also put it in the in-memory
  semantic index, the way the summarizer does after a real generation.
  """
  def summary_fixture(act, attrs \\ %{}) do
    attrs = Map.new(attrs)

    summary =
      %Summary{}
      |> Summary.changeset(
        Enum.into(attrs, %{
          act_id: act.id,
          plain_text: "resumo do diploma #{act.id}",
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
      )
      |> Repo.insert!()

    if vector = attrs[:embedding], do: Index.put(summary.id, act.id, vector)

    summary
  end
end
