defmodule OQueMudou.Register.Summary do
  @moduledoc """
  A plain-language summary + life-domain classification of an `Act`.

  Produced by the summarizer (one LLM call yields `plain_text` + `domains`).
  `model`/`prompt_version` are recorded per summary for provenance.
  `validated_at` is the private human-validation safety net (null = unvalidated).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias OQueMudou.Register
  alias OQueMudou.Register.Act

  schema "summaries" do
    field :plain_text, :string

    field :domains, {:array, Ecto.Enum},
      values: Register.life_domains() |> Enum.map(&String.to_atom/1),
      default: []

    field :model, :string
    field :prompt_version, :string
    field :status, Ecto.Enum, values: Register.statuses(), default: :unreviewed
    field :generated_at, :utc_datetime
    field :validated_at, :utc_datetime

    belongs_to :act, Act

    timestamps(type: :utc_datetime)
  end

  @required ~w(act_id plain_text)a
  @optional ~w(domains model prompt_version status generated_at validated_at)a

  def changeset(summary, attrs) do
    summary
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> assoc_constraint(:act)
  end
end
