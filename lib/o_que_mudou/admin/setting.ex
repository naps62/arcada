defmodule OQueMudou.Admin.Setting do
  @moduledoc """
  Singleton row holding the **active** summarizer selection — the provider +
  model used by the daily cron / auto-summarize. Manual per-act runs can use any
  provider+model and don't touch this. Edited on `/admin`.

  (Legacy per-adapter columns from the pre-providers design remain in the table
  but are no longer mapped.)
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias OQueMudou.Providers.Provider

  schema "settings" do
    field :active_model, :string
    belongs_to :active_provider, Provider

    timestamps(type: :utc_datetime)
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:active_provider_id, :active_model])
    |> blank_to_nil([:active_provider_id, :active_model])
    |> assoc_constraint(:active_provider)
  end

  defp blank_to_nil(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, cs ->
      if get_change(cs, field) == "", do: force_change(cs, field, nil), else: cs
    end)
  end
end
