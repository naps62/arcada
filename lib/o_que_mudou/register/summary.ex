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
  alias OQueMudou.Providers.Provider

  schema "summaries" do
    field :plain_text, :string

    field :domains, {:array, Ecto.Enum},
      values: Register.life_domains() |> Enum.map(&String.to_atom/1),
      default: []

    field :model, :string
    field :prompt_version, :string
    field :status, Ecto.Enum, values: Register.statuses(), default: :unreviewed
    # The act's full text was capped before summarising (oversized diploma): the
    # summary reflects only part of the document, not the whole thing.
    field :truncated, :boolean, default: false
    # How the text was prepared: "full" | "rank" (relevant sections kept) |
    # "truncate" (opening kept). Null on legacy rows. See OQueMudou.Summarizer.
    field :text_strategy, :string
    # The embeddings model that ranked the sections (preprocessor), set only when
    # text_strategy = "rank". Distinct from `model` (the LLM that wrote the text).
    field :ranker_model, :string
    field :generated_at, :utc_datetime
    field :validated_at, :utc_datetime

    belongs_to :act, Act
    belongs_to :provider, Provider

    timestamps(type: :utc_datetime)
  end

  @required ~w(act_id plain_text)a
  @optional ~w(domains model prompt_version status truncated text_strategy ranker_model provider_id generated_at validated_at)a

  def changeset(summary, attrs) do
    summary
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> assoc_constraint(:act)
  end
end
