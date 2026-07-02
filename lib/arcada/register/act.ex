defmodule Arcada.Register.Act do
  @moduledoc """
  A single act published in an edition (Decreto-Lei, Portaria, …).

  `dre_id` is the DRE-assigned identifier (the OutSystems `DbId`) and is the
  idempotency key the scraper upserts on. See `docs/endpoints.md`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Arcada.Register.{Edition, Summary}

  schema "acts" do
    field :dre_id, :string
    field :tipo, :string
    field :emitter, :string
    field :title, :string
    field :full_text, :string
    field :source_url, :string
    field :pdf_url, :string
    field :published_at, :date

    belongs_to :edition, Edition
    has_many :summaries, Summary
    belongs_to :published_summary, Summary

    timestamps(type: :utc_datetime)
  end

  @required ~w(edition_id dre_id)a
  @optional ~w(tipo emitter title full_text source_url pdf_url published_at published_summary_id)a

  def changeset(act, attrs) do
    act
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> assoc_constraint(:edition)
    |> unique_constraint(:dre_id)
  end
end
