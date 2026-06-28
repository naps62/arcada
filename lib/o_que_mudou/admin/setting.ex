defmodule OQueMudou.Admin.Setting do
  @moduledoc """
  The single-row, runtime-editable summarizer configuration. Each field is
  optional; a `nil` means "use the env-var default" (see `config/runtime.exs`).
  Edited from the `/admin/summarizer` page, read by `OQueMudou.Admin`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @adapters ~w(manual api ssh local)

  schema "settings" do
    field :summarizer_adapter, :string
    field :api_model, :string
    field :api_key, :string
    field :ssh_host, :string
    field :ssh_user, :string
    field :ssh_claude_cmd, :string
    field :ssh_model, :string

    timestamps(type: :utc_datetime)
  end

  @fields ~w(summarizer_adapter api_model api_key ssh_host ssh_user ssh_claude_cmd ssh_model)a

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, @fields)
    |> validate_inclusion(:summarizer_adapter, @adapters)
    |> blank_to_nil()
  end

  @doc "The adapter names valid in the admin form (matches `Summarizer` keys)."
  def adapters, do: @adapters

  # Empty form fields arrive as "" — store them as nil so they fall back to env.
  defp blank_to_nil(changeset) do
    Enum.reduce(@fields, changeset, fn field, cs ->
      case get_change(cs, field) do
        "" -> force_change(cs, field, nil)
        _ -> cs
      end
    end)
  end
end
