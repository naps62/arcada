defmodule OQueMudou.Admin do
  @moduledoc """
  Runtime-editable summarizer configuration, the source of truth that overrides
  the boot-time env-var defaults.

  Precedence is **DB override ?? env default**: a setting that's `nil` falls back
  to `config/runtime.exs`, so the admin page only has to set what it wants to
  change. Reads happen per summarize job (cheap), so edits take effect on the next
  job without a restart — except Oban queue concurrency, which is fixed at boot.
  """
  import Ecto.Query, warn: false

  alias OQueMudou.Repo
  alias OQueMudou.Admin.Setting
  alias OQueMudou.Summarizer.Adapters.{Api, Ssh}

  @adapter_strings ~w(manual api ssh local)

  @doc "The settings row, or an unpersisted default struct (all-nil → env fallback)."
  def get_settings, do: Repo.one(singleton_query()) || %Setting{}

  @doc "Changeset for the admin form."
  def change_settings(%Setting{} = settings \\ get_settings(), attrs \\ %{}),
    do: Setting.changeset(settings, attrs)

  @doc """
  Upsert the singleton settings row. A blank `api_key` is treated as "leave the
  stored key unchanged" (so the form never has to re-display the secret).
  """
  def update_settings(attrs) do
    settings = Repo.one(singleton_query()) || %Setting{}

    settings
    |> Setting.changeset(drop_blank_secret(attrs, settings))
    |> Repo.insert_or_update()
  end

  ## Resolver — called by the summarizer

  @doc "Effective summarizer adapter: DB value (whitelisted) else env default."
  def summarizer_adapter do
    case get_settings().summarizer_adapter do
      a when a in @adapter_strings -> String.to_existing_atom(a)
      _ -> env_summarizer_adapter()
    end
  end

  @doc "Effective config for an adapter module: env config overlaid with DB overrides."
  def adapter_config(module) do
    Keyword.merge(Application.get_env(:o_que_mudou, module, []), db_overrides(module))
  end

  defp env_summarizer_adapter,
    do: Application.get_env(:o_que_mudou, OQueMudou.Summarizer, [])[:adapter] || :manual

  defp db_overrides(Api) do
    s = get_settings()
    compact(model: s.api_model, api_key: s.api_key)
  end

  defp db_overrides(Ssh) do
    s = get_settings()
    compact(host: s.ssh_host, user: s.ssh_user, claude_cmd: s.ssh_claude_cmd, model: s.ssh_model)
  end

  defp db_overrides(_module), do: []

  defp compact(kw), do: Enum.reject(kw, fn {_k, v} -> is_nil(v) end)

  defp singleton_query, do: from(s in Setting, order_by: [asc: s.id], limit: 1)

  defp drop_blank_secret(attrs, _settings) do
    case Map.get(attrs, "api_key") do
      blank when blank in [nil, ""] -> Map.delete(attrs, "api_key")
      _ -> attrs
    end
  end
end
