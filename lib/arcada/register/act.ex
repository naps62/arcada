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

  @doc """
  Decorative URL slug for an act, e.g. `decreto-n-84-2026`.

  Derived from the stable `title` (falling back to `tipo`) — never the summary
  headline, which changes on re-summarization and would churn canonical URLs.
  The slug is cosmetic: act lookup keys on `dre_id`, so a stale slug still
  resolves and the canonical tag reconciles it. Works on any struct/map exposing
  `:title` and `:tipo`.
  """
  def slug(%{title: title, tipo: tipo}) do
    case slugify(title) do
      "" -> slugify(tipo)
      s -> s
    end
    |> case do
      "" -> "ato"
      s -> s
    end
  end

  defp slugify(text) when is_binary(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> String.slice(0, 80)
    |> String.trim("-")
  end

  defp slugify(_), do: ""
end
