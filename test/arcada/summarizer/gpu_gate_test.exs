defmodule Arcada.Summarizer.GpuGateTest do
  # async: false — mutates the process-wide GpuGate app env (the injected probe).
  use ExUnit.Case, async: false

  alias Arcada.Summarizer.GpuGate

  # Point the gate at a stub probe returning `{output, exit_status}`, restoring
  # the prior config afterwards.
  defp set_gate(kw) do
    prev = Application.get_env(:arcada, GpuGate, [])
    Application.put_env(:arcada, GpuGate, kw)
    on_exit(fn -> Application.put_env(:arcada, GpuGate, prev) end)
  end

  defp probe(csv), do: fn -> {csv, 0} end

  test "idle GPU (no compute processes) is available" do
    set_gate(probe: probe(""))
    assert GpuGate.check() == :ok
    assert GpuGate.available?()
  end

  test "only our own processes on the GPU is still available" do
    set_gate(probe: probe("12, llama-server, 8000\n15, llama-server, 512"))
    assert GpuGate.check() == :ok
  end

  test "a foreign process holding the GPU makes it busy" do
    set_gate(probe: probe("12, llama-server, 8000\n99, python, 4000"))

    assert {:busy, {:foreign_gpu_processes, [%{name: "python", pid: "99"}]}} = GpuGate.check()
    refute GpuGate.available?()
  end

  test "custom own_processes allowlist reclassifies a name as ours" do
    set_gate(probe: probe("99, my-trainer, 4000"), own_processes: ["my-trainer"])
    assert GpuGate.check() == :ok
  end

  test "disabled gate is always available, without probing" do
    set_gate(enabled: false, probe: fn -> raise "probe must not run when disabled" end)
    assert GpuGate.check() == :ok
  end

  test "a non-zero probe exit fails open (allows backfill)" do
    set_gate(probe: fn -> {"nvidia-smi: command not found", 127} end)
    assert GpuGate.check() == :ok
  end

  test "a raising probe fails open (allows backfill)" do
    set_gate(probe: fn -> raise "boom" end)
    assert GpuGate.check() == :ok
  end

  test "snooze_seconds is configurable with a default" do
    set_gate([])
    assert GpuGate.snooze_seconds() == 30
    set_gate(snooze_seconds: 5)
    assert GpuGate.snooze_seconds() == 5
  end
end
