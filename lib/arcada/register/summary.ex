defmodule Arcada.Register.Summary do
  @moduledoc """
  A plain-language summary + life-domain classification of an `Act`.

  Produced by the summarizer (one LLM call yields `plain_text` + `domains`).
  `model`/`prompt_version` are recorded per summary for provenance.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Arcada.Register
  alias Arcada.Register.Act
  alias Arcada.Providers.Provider

  schema "summaries" do
    field :plain_text, :string
    # Short plain-language headline ("what changed", ~6-10 words) shown as the
    # story headline in place of the act's formal designation. Null on legacy
    # rows / summaries that predate this field.
    field :headline, :string

    field :domains, {:array, Ecto.Enum},
      values: Register.life_domains() |> Enum.map(&String.to_atom/1),
      default: []

    field :model, :string
    field :prompt_version, :string
    # The act's full text was capped before summarising (oversized diploma): the
    # summary reflects only part of the document, not the whole thing.
    field :truncated, :boolean, default: false
    # How the text was prepared: "full" | "rank" (relevant sections kept) |
    # "truncate" (opening kept). Null on legacy rows. See Arcada.Summarizer.
    field :text_strategy, :string
    # The embeddings model that ranked the sections (preprocessor), set only when
    # text_strategy = "rank". Distinct from `model` (the LLM that wrote the text).
    field :ranker_model, :string
    # Token usage + cost for the run that produced this summary. `cost_source`:
    # "api" = exact tokens × price table; "subscription" = SSH CLI's notional
    # cost (covered by a Claude subscription, not real spend); null when the
    # backend reports no usable cost. See the add_usage_to_summaries migration.
    field :input_tokens, :integer
    field :output_tokens, :integer
    field :cost_usd, :decimal
    field :cost_source, :string
    field :duration_ms, :integer
    field :generated_at, :utc_datetime
    # bge-m3 embedding of `plain_text`, for semantic search (issue #27). Null
    # when the embeddings server was disabled/unreachable at generation time —
    # such summaries are simply absent from search results, never an error.
    field :embedding, Arcada.Register.Embedding

    belongs_to :act, Act
    belongs_to :provider, Provider

    timestamps(type: :utc_datetime)
  end

  @required ~w(act_id plain_text)a
  @optional ~w(headline domains model prompt_version truncated text_strategy ranker_model input_tokens output_tokens cost_usd cost_source duration_ms provider_id generated_at embedding)a

  def changeset(summary, attrs) do
    summary
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> assoc_constraint(:act)
  end

  # The summarizer wraps unavoidable technical terms in `[[…]]` so a glossary /
  # tooltip can be attached later (see the base system prompt). The markers are
  # kept verbatim in `plain_text`/`headline` for that future use, but stripped
  # everywhere they'd otherwise leak: public display, meta/SEO, search and the
  # embedding input. The admin compare view deliberately shows the raw markers.
  @term_marker ~r/\[\[(.+?)\]\]/

  @doc "Strip `[[term]]` tooltip markers to plain text for display/search/embedding."
  def strip_terms(nil), do: nil
  def strip_terms(text) when is_binary(text), do: Regex.replace(@term_marker, text, "\\1")
end
