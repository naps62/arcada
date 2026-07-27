defmodule Mix.Tasks.Arcada.Grafana do
  @shortdoc "Sync Grafana dashboards between priv/grafana and a Grafana instance"
  @moduledoc """
  Dashboards as code. `priv/grafana/*.json` is the source of truth; this task moves
  them to and from a live Grafana. See `docs/OBSERVABILITY.md` § 5.

      mix arcada.grafana pull <uid>      # Grafana -> priv/grafana/<uid>.json
      mix arcada.grafana push [uid]      # priv/grafana -> Grafana (all files if uid omitted)
      mix arcada.grafana push <uid> --force
      mix arcada.grafana list [--live]   # what is on disk (and, with --live, how stale it is)

  Needs `GRAFANA_URL` and `GRAFANA_SERVICE_ACCOUNT_TOKEN` in the environment.

  ## File format

  `pull` writes the `POST /api/dashboards/db` payload minus the flags:

      {"folderUid": "o-que-mudou", "dashboard": {...}}

  `folderUid` is stored because it is *not* part of the dashboard object — pushing
  without it relocates the dashboard to the General folder. To hand-import one into
  the Grafana UI, feed it `jq .dashboard`.

  This wrapper is the only accepted shape. A bare dashboard object — what the Grafana
  UI's "export JSON" gives you — has nowhere to carry `folderUid` or `version`, so
  push could neither place it nor guard it. To start tracking a dashboard, create it
  in the UI and `pull` it; don't hand-write the file.

  `pull` drops `id` (per-instance row id) and the whole `meta` block (timestamps,
  permissions, url) and re-encodes with sorted keys, so a pull with no human edit in
  between is a no-op diff. `version` is deliberately kept — see below.

  Grafana rewrites `schemaVersion` and migrates panel internals across its own
  upgrades, so the first pull after a Grafana upgrade produces a large but legitimate
  diff. That is Grafana changing the dashboard, not this normalisation failing — do
  not widen the strip list to silence it.

  ## Why push refuses by default

  `version` is Grafana's optimistic-concurrency token. Push sends it with
  `overwrite: false`, so a dashboard that was edited in the Grafana UI since the last
  pull makes the push fail with HTTP 412 instead of silently destroying that edit.
  This is the whole point of versioning the files: the failure mode we are protecting
  against is losing hand-tuned panels, and an unconditional overwrite reintroduces it.

  `--force` sends `overwrite: true` and wins regardless. Use it after looking at what
  you are discarding.

  A successful push writes the new version back into the local file, so pushing twice
  in a row works without an intervening pull.
  """
  use Mix.Task

  @requirements ["app.config"]

  @dir "priv/grafana"

  # Per-instance, changes with no human edit. `version` is NOT dropped: push needs it
  # as the concurrency token.
  @drop_dashboard_keys ~w(id)

  @impl Mix.Task
  def run(argv) do
    {:ok, _} = Application.ensure_all_started(:req)

    case argv do
      ["pull", uid] -> pull(uid)
      ["push" | rest] -> push_cmd(rest)
      ["list" | rest] -> list_cmd(rest)
      _ -> Mix.raise(usage(argv))
    end
  end

  defp usage(argv) do
    """
    unknown arguments: #{Enum.join(argv, " ")}

    usage:
      mix arcada.grafana pull <uid>
      mix arcada.grafana push [uid] [--force]
      mix arcada.grafana list [--live]
    """
  end

  ## pull

  defp pull(uid) do
    body = request!(:get, "/api/dashboards/uid/#{uid}")
    doc = normalize(body)
    path = path_for(uid)

    File.mkdir_p!(@dir)
    File.write!(path, canonical_json(doc))

    Mix.shell().info(
      "pulled #{uid} v#{doc["dashboard"]["version"]} " <>
        "(#{length(doc["dashboard"]["panels"] || [])} panels, folder #{inspect(doc["folderUid"])}) " <>
        "-> #{path}"
    )
  end

  @doc false
  def normalize(%{"dashboard" => dashboard} = body) do
    %{
      "folderUid" => get_in(body, ["meta", "folderUid"]) || "",
      "dashboard" => Map.drop(dashboard, @drop_dashboard_keys)
    }
  end

  def normalize(body), do: Mix.raise("unexpected Grafana response: #{inspect(body, limit: 5)}")

  ## push

  defp push_cmd(rest) do
    {opts, args, _} = OptionParser.parse(rest, switches: [force: :boolean])
    force? = Keyword.get(opts, :force, false)

    uids =
      case args do
        [uid] -> [uid]
        [] -> local_uids()
        _ -> Mix.raise(usage(["push" | rest]))
      end

    if uids == [], do: Mix.raise("no dashboards in #{@dir}/")

    # Raises on the first failure; anything already pushed stays pushed and is logged.
    Enum.each(uids, &push(&1, force?))
  end

  defp push(uid, force?) do
    path = path_for(uid)
    doc = read_doc!(path)

    payload =
      %{
        "dashboard" => doc["dashboard"],
        "folderUid" => doc["folderUid"] || "",
        "overwrite" => force?,
        "message" => "mix arcada.grafana push"
      }

    case request(:post, "/api/dashboards/db", json: payload) do
      {status, body} when status in 200..299 ->
        version = body["version"]
        File.write!(path, canonical_json(put_in(doc, ["dashboard", "version"], version)))
        Mix.shell().info("pushed #{uid} -> v#{version}")

      {412, body} ->
        Mix.raise("""
        #{uid}: Grafana refused the push — the live dashboard has moved on (HTTP 412).
        Grafana said: #{grafana_message(body)}

        Local copy is at version #{get_in(doc, ["dashboard", "version"])}. Someone saved
        an edit in the Grafana UI since it was pulled; pushing would destroy it.

          mix arcada.grafana pull #{uid}     # take the live copy, then re-apply your change
          mix arcada.grafana push #{uid} --force   # or discard the live edit on purpose
        """)

      {status, body} ->
        Mix.raise("#{uid}: push failed (HTTP #{status}): #{grafana_message(body)}")
    end
  end

  ## list

  defp list_cmd(rest) do
    {opts, _, _} = OptionParser.parse(rest, switches: [live: :boolean])

    case local_uids() do
      [] ->
        Mix.shell().info("no dashboards in #{@dir}/")

      uids ->
        Enum.each(uids, fn uid ->
          d = read_doc!(path_for(uid))["dashboard"]
          suffix = if opts[:live], do: live_suffix(uid, d["version"]), else: ""

          Mix.shell().info(
            "#{String.pad_trailing(uid, 20)} v#{d["version"] || "-"}  #{d["title"]}#{suffix}"
          )
        end)
    end
  end

  defp live_suffix(uid, local_version) do
    case request(:get, "/api/dashboards/uid/#{uid}") do
      {status, body} when status in 200..299 ->
        live = get_in(body, ["dashboard", "version"])
        if live == local_version, do: "  [in sync]", else: "  [STALE: live is v#{live}]"

      {404, _} ->
        "  [not in Grafana]"

      {status, body} ->
        "  [lookup failed: HTTP #{status} #{grafana_message(body)}]"
    end
  end

  ## files

  defp path_for(uid), do: Path.join(@dir, uid <> ".json")

  defp local_uids do
    @dir |> Path.join("*.json") |> Path.wildcard() |> Enum.map(&Path.basename(&1, ".json"))
  end

  @doc false
  def read_doc!(path) do
    unless File.exists?(path), do: Mix.raise("no such dashboard file: #{path}")

    case path |> File.read!() |> Jason.decode() do
      {:ok, %{"folderUid" => _, "dashboard" => %{"uid" => _}} = doc} ->
        doc

      {:ok, _} ->
        Mix.raise(wrong_shape(path))

      {:error, e} ->
        Mix.raise("#{path}: invalid JSON — #{Exception.message(e)}")
    end
  end

  defp wrong_shape(path) do
    uid = Path.basename(path, ".json")

    """
    #{path}: not in the expected shape.

    Every file in #{@dir}/ must look like:

        {"folderUid": "<folder uid>", "dashboard": {"uid": "...", "title": ..., ...}}

    A bare dashboard object (Grafana's "export JSON") is not enough — it carries no
    folder and no version, so push could neither place the dashboard nor detect a
    conflicting live edit. Create the dashboard in Grafana, then:

        mix arcada.grafana pull #{uid}
    """
  end

  @doc false
  def canonical_json(data), do: Jason.encode!(sort_keys(data), pretty: true) <> "\n"

  defp sort_keys(map) when is_map(map) and not is_struct(map) do
    map
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {k, v} -> {k, sort_keys(v)} end)
    |> Jason.OrderedObject.new()
  end

  defp sort_keys(list) when is_list(list), do: Enum.map(list, &sort_keys/1)
  defp sort_keys(other), do: other

  ## http

  defp request!(method, path, opts \\ []) do
    case request(method, path, opts) do
      {status, body} when status in 200..299 ->
        body

      {status, body} ->
        Mix.raise("Grafana #{method} #{path} failed (HTTP #{status}): #{grafana_message(body)}")
    end
  end

  defp request(method, path, opts \\ []) do
    {base, token} = credentials()

    options =
      [
        method: method,
        url: base <> path,
        headers: [{"authorization", "Bearer " <> token}],
        retry: false
      ] ++ opts

    case Req.request(options) do
      {:ok, %Req.Response{status: status, body: body}} ->
        {status, body}

      {:error, exception} ->
        Mix.raise("cannot reach Grafana at #{base}: #{Exception.message(exception)}")
    end
  end

  defp credentials do
    base =
      System.get_env("GRAFANA_URL") ||
        Mix.raise("GRAFANA_URL is not set (e.g. https://grafana.example.com)")

    token =
      System.get_env("GRAFANA_SERVICE_ACCOUNT_TOKEN") ||
        Mix.raise("GRAFANA_SERVICE_ACCOUNT_TOKEN is not set (Grafana service account token)")

    {String.trim_trailing(base, "/"), token}
  end

  defp grafana_message(%{} = body), do: body["message"] || inspect(body, limit: 10)
  defp grafana_message(body) when is_binary(body), do: String.slice(body, 0, 500)
  defp grafana_message(body), do: inspect(body, limit: 10)
end
