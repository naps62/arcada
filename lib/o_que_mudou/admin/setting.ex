defmodule OQueMudou.Admin.Setting do
  @moduledoc """
  Singleton row holding runtime-editable summarizer config, edited on `/admin`:

    * the **active** provider + model used by the daily cron / auto-summarize
      (manual per-act runs pick their own and don't touch this);
    * how oversized diplomas are handled — `max_text_chars` (the prompt cap) and
      the embeddings server (`embeddings_base_url`/`embeddings_model`) that ranks
      a long act's sections so the change-bearing ones are kept over annexes.

  Every field is nullable — a null falls back to the env/config default.

  (Legacy per-adapter columns from the pre-providers design remain in the table
  but are no longer mapped.)
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias OQueMudou.Providers.Provider

  @nilable_strings [:active_provider_id, :active_model, :embeddings_base_url, :embeddings_model]

  schema "settings" do
    field :active_model, :string
    belongs_to :active_provider, Provider

    field :max_text_chars, :integer
    field :embeddings_base_url, :string
    field :embeddings_model, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(setting, attrs) do
    setting
    |> cast(
      blankify(attrs),
      [:active_provider_id, :active_model, :max_text_chars] ++
        [:embeddings_base_url, :embeddings_model]
    )
    |> blank_to_nil(@nilable_strings)
    |> validate_number(:max_text_chars, greater_than: 0)
    |> assoc_constraint(:active_provider)
  end

  # Turn "" into nil before casting so blank numeric/optional inputs from the
  # admin form become nil (fall back to defaults) instead of cast errors.
  defp blankify(attrs) when is_map(attrs) do
    Map.new(attrs, fn {k, v} -> {k, if(v == "", do: nil, else: v)} end)
  end

  defp blank_to_nil(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, cs ->
      if get_change(cs, field) == "", do: force_change(cs, field, nil), else: cs
    end)
  end
end
