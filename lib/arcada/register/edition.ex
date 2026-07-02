defmodule Arcada.Register.Edition do
  @moduledoc """
  A Diário da República edition (issue), e.g. Série I n.º 118/2026.

  One edition groups the `Act`s published on a given business day.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Arcada.Register.Act

  schema "editions" do
    field :serie, :string
    field :number, :string
    field :date, :date
    field :sumario_url, :string
    field :scraped_at, :utc_datetime

    has_many :acts, Act

    timestamps(type: :utc_datetime)
  end

  @required ~w(serie number date)a
  @optional ~w(sumario_url scraped_at)a

  def changeset(edition, attrs) do
    edition
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint([:serie, :number])
  end
end
