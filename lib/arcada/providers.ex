defmodule Arcada.Providers do
  @moduledoc """
  CRUD for summarizer `Provider` instances (issue #20). The summarizer dispatches
  on `provider.kind`; the active provider+model (held in `Arcada.Admin`
  settings) drives auto-summarize, while any provider+model can be used for a
  manual per-act run.
  """
  import Ecto.Query, warn: false

  alias Arcada.Repo
  alias Arcada.Providers.Provider

  def list_providers, do: Repo.all(from p in Provider, order_by: [asc: p.name])

  def enabled_providers,
    do: Repo.all(from p in Provider, where: p.enabled == true, order_by: [asc: p.name])

  def get_provider!(id), do: Repo.get!(Provider, id)
  def get_provider(id) when is_integer(id) or is_binary(id), do: Repo.get(Provider, id)
  def get_provider(nil), do: nil

  def change_provider(%Provider{} = provider, attrs \\ %{}),
    do: Provider.changeset(provider, attrs)

  def create_provider(attrs), do: %Provider{} |> Provider.changeset(attrs) |> Repo.insert()

  def update_provider(%Provider{} = provider, attrs),
    do: provider |> Provider.changeset(attrs) |> Repo.update()

  def delete_provider(%Provider{} = provider), do: Repo.delete(provider)
end
