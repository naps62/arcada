defmodule OQueMudou.Providers.Provider do
  @moduledoc """
  A configured summarizer backend instance. `kind` selects the adapter:

    * `:anthropic` — Claude Messages API (`api_key`, `models`).
    * `:openai`    — any OpenAI-compatible `/v1/chat/completions` endpoint
                     (`base_url` + `api_key`), e.g. llmbase, ollama, synthetic.new.
    * `:ssh`       — run a CLI (`ssh_claude_cmd`, default `claude -p`) over SSH on
                     a host that's already authenticated (`ssh_host`/`ssh_user`/…).

  `models` is the list of model identifiers this instance offers; one is chosen
  per summary (the active model for auto-runs, or any of them for a manual run).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds [:anthropic, :openai, :ssh]

  schema "providers" do
    field :name, :string
    field :kind, Ecto.Enum, values: @kinds
    field :base_url, :string
    field :api_key, :string
    field :ssh_host, :string
    field :ssh_user, :string
    field :ssh_identity_file, :string
    field :ssh_claude_cmd, :string
    field :models, {:array, :string}, default: []
    field :max_concurrency, :integer
    field :enabled, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  @doc "Default max summarize concurrency for a kind: SSH = 1 session, API = 5."
  def default_max_concurrency(:ssh), do: 1
  def default_max_concurrency(_), do: 5

  @doc "Effective max concurrency: the stored value, or the per-kind default."
  def max_concurrency(%__MODULE__{max_concurrency: n}) when is_integer(n) and n > 0, do: n
  def max_concurrency(%__MODULE__{kind: kind}), do: default_max_concurrency(kind)

  @required ~w(name kind)a
  @optional ~w(base_url api_key ssh_host ssh_user ssh_identity_file ssh_claude_cmd models max_concurrency enabled)a

  def changeset(provider, attrs) do
    provider
    |> cast(normalize(attrs), @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:kind, @kinds)
    |> validate_kind_fields()
    |> put_default_max_concurrency()
    |> validate_number(:max_concurrency, greater_than: 0)
    |> unique_constraint(:name)
  end

  # SSH is capped at 1 by default; API-style providers fan out. An explicit value
  # from the admin form always wins.
  defp put_default_max_concurrency(changeset) do
    if get_field(changeset, :max_concurrency) do
      changeset
    else
      put_change(
        changeset,
        :max_concurrency,
        default_max_concurrency(get_field(changeset, :kind))
      )
    end
  end

  # Accept `models` as a newline/comma-separated string from the admin form.
  defp normalize(%{} = attrs) do
    case Map.get(attrs, "models") do
      m when is_binary(m) -> Map.put(attrs, "models", split_models(m))
      _ -> attrs
    end
  end

  defp split_models(str) do
    str
    |> String.split(~r/[\n,]/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp validate_kind_fields(changeset) do
    case get_field(changeset, :kind) do
      :openai -> validate_required(changeset, [:base_url])
      :ssh -> validate_required(changeset, [:ssh_host])
      _ -> changeset
    end
  end
end
