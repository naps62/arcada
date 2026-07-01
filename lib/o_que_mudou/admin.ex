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

  @doc """
  Effective cap (chars) on act text fed to the summarizer for `model`:
  DB setting ?? app config ?? adaptive per-model cap derived from the model's
  context window (`OQueMudou.Summarizer.ContextWindow`, issue #18). The first two
  are explicit operator overrides; only the fallback is adaptive. `model` is `nil`
  when unknown, which yields the conservative default window.
  """
  def max_text_chars(model \\ nil) do
    get_settings().max_text_chars ||
      Application.get_env(:o_que_mudou, OQueMudou.Summarizer, [])[:max_text_chars] ||
      OQueMudou.Summarizer.ContextWindow.cap_for(model)
  end

  @doc """
  Effective embeddings config (for oversized-diploma section ranking): the
  `OQueMudou.Summarizer.Embeddings` app config overlaid with DB overrides
  (`base_url`, `model`). Ranking is active iff a `base_url` ends up set (or a
  test `:embed_fn` is injected).
  """
  def embeddings_config do
    s = get_settings()

    Keyword.merge(
      Application.get_env(:o_que_mudou, OQueMudou.Summarizer.Embeddings, []),
      compact(base_url: s.embeddings_base_url, model: s.embeddings_model)
    )
  end

  defp compact(kw), do: Enum.reject(kw, fn {_k, v} -> is_nil(v) end)

  defp singleton_query, do: from(s in Setting, order_by: [asc: s.id], limit: 1)
end
