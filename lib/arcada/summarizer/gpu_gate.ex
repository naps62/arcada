defmodule Arcada.Summarizer.GpuGate do
  @moduledoc """
  Yield-to-the-GPU gate for **backfill** summaries (historical backfill job).

  A backfill summary is background work: it must step aside for anything else on
  the GPU box — a one-off local job, your own work on the RTX card, another
  service — not just for the daily pipeline. The daily pipeline is handled
  separately (higher Oban priority + the per-provider `Concurrency` limit); this
  gate is only about foreign, *non-amalia* GPU load.

  Free-VRAM is a useless signal here: amalia is a resident `llama-server`, so the
  model (and its preallocated KV cache) hold VRAM whether or not a request is in
  flight. Instead we attribute GPU **processes**: `nvidia-smi` lists every
  process with a compute context; if any of them isn't one of ours
  (`:own_processes`, matched by substring), a foreign job is using the card and
  the backfill snoozes until it's gone.

  Config (`config :arcada, Arcada.Summarizer.GpuGate, ...`):

    * `:enabled` — master switch (default `true`)
    * `:own_processes` — process-name substrings that are *ours*, not foreign
      (default `["llama-server", "ollama"]` — amalia + a co-located embeddings
      server both count as ours)
    * `:snooze_seconds` — how long a gated backfill job defers (default `30`)
    * `:probe` — how to sample the GPU. Either a `{cmd, args}` tuple run with
      `System.cmd/3`, or a 0-arity function returning `{output, exit_status}`
      (tests inject this). Defaults to a **local** `nvidia-smi`; point it at
      `{"ssh", ["gpubox", "nvidia-smi", ...]}` when the app runs off the GPU box.

  **Fails open.** A missing/broken probe (no `nvidia-smi`, ssh down, non-zero
  exit) logs a warning and returns `:ok` — a broken probe must never wedge the
  backfill forever, and the per-provider `Concurrency` limit still keeps amalia
  itself to one summary at a time regardless.
  """
  require Logger

  @default_probe {"nvidia-smi",
                  [
                    "--query-compute-apps=pid,process_name,used_memory",
                    "--format=csv,noheader,nounits"
                  ]}
  @default_own ["llama-server", "ollama"]
  @default_snooze 30

  @doc "Seconds a gated backfill job should snooze before retrying."
  def snooze_seconds, do: cfg(:snooze_seconds, @default_snooze)

  @doc """
  `:ok` when the GPU is free of foreign processes (a backfill summary may run),
  or `{:busy, {:foreign_gpu_processes, procs}}` when a non-amalia process holds
  the card. Disabled or a failed probe → `:ok` (fail open).
  """
  @spec check() :: :ok | {:busy, {:foreign_gpu_processes, [map()]}}
  def check do
    if cfg(:enabled, true) do
      case foreign_processes() do
        {:ok, []} ->
          :ok

        {:ok, procs} ->
          {:busy, {:foreign_gpu_processes, procs}}

        {:error, reason} ->
          Logger.warning("GpuGate probe failed (#{inspect(reason)}); allowing backfill")
          :ok
      end
    else
      :ok
    end
  end

  @doc "Convenience boolean: `true` when a backfill summary may run right now."
  def available?, do: check() == :ok

  # GPU compute processes whose name isn't in the `:own_processes` allowlist.
  defp foreign_processes do
    with {:ok, output} <- run_probe() do
      own = cfg(:own_processes, @default_own)

      procs =
        output
        |> String.split("\n", trim: true)
        |> Enum.map(&parse_row/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.reject(fn %{name: name} -> own?(name, own) end)

      {:ok, procs}
    end
  end

  defp own?(name, own), do: Enum.any?(own, &String.contains?(name, &1))

  # One CSV row: "pid, process_name, used_mib". Blank/malformed rows are dropped.
  defp parse_row(row) do
    case row |> String.split(",", parts: 3) |> Enum.map(&String.trim/1) do
      [pid, name, mem] when name != "" -> %{pid: pid, name: name, used_mib: mem}
      _ -> nil
    end
  end

  defp run_probe do
    case cfg(:probe, @default_probe) do
      fun when is_function(fun, 0) -> normalize(fun.())
      {cmd, args} -> normalize(System.cmd(cmd, args, stderr_to_stdout: true))
    end
  rescue
    e -> {:error, e}
  end

  defp normalize({output, 0}) when is_binary(output), do: {:ok, output}
  defp normalize({output, status}), do: {:error, {:exit_status, status, output}}

  defp cfg(key, default), do: Keyword.get(config(), key, default)
  defp config, do: Application.get_env(:arcada, __MODULE__, [])
end
