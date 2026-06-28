defmodule OQueMudou.Admin do
  @moduledoc """
  The active summarizer selection (provider + model) used by the daily cron /
  auto-summarize. Held in a singleton `settings` row. Manual per-act runs pick
  their own provider+model and don't read this.
  """
  import Ecto.Query, warn: false

  alias OQueMudou.Repo
  alias OQueMudou.Admin.Setting

  @doc "The settings row (active provider preloaded), or an unpersisted default."
  def get_settings do
    (Repo.one(singleton_query()) || %Setting{})
    |> Repo.preload(:active_provider)
  end

  @doc "Changeset for the active-selection form."
  def change_settings(%Setting{} = settings \\ %Setting{}, attrs \\ %{}),
    do: Setting.changeset(settings, attrs)

  @doc "Upsert the singleton settings row."
  def update_settings(attrs) do
    settings = Repo.one(singleton_query()) || %Setting{}

    settings
    |> Setting.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc "The active provider (or nil) used for auto-summarize."
  def active_provider, do: get_settings().active_provider

  @doc "The active model string (or nil)."
  def active_model, do: get_settings().active_model

  defp singleton_query, do: from(s in Setting, order_by: [asc: s.id], limit: 1)
end
