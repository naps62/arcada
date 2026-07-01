defmodule OQueMudou.Summarizer.ContextWindowTest do
  use ExUnit.Case, async: false

  alias OQueMudou.Summarizer.ContextWindow

  # Swap the app config for the duration of a test, restoring it after.
  defp put_cfg(kw) do
    prev = Application.get_env(:o_que_mudou, ContextWindow, [])
    Application.put_env(:o_que_mudou, ContextWindow, Keyword.merge(prev, kw))
    on_exit(fn -> Application.put_env(:o_que_mudou, ContextWindow, prev) end)
  end

  describe "window_for/1" do
    test "known Claude prefixes get the 1M window" do
      assert ContextWindow.window_for("claude-cli") == 1_000_000
      assert ContextWindow.window_for("claude-sonnet-4-6") == 1_000_000
      assert ContextWindow.window_for("claude-opus-4-8") == 1_000_000
    end

    test "unknown / local / nil models fall back to the conservative default" do
      assert ContextWindow.window_for("some-local-8b") == 200_000
      assert ContextWindow.window_for(nil) == 200_000
    end

    test "the longest matching prefix wins" do
      put_cfg(windows: %{"claude" => 100, "claude-cli" => 999})
      assert ContextWindow.window_for("claude-cli") == 999
      assert ContextWindow.window_for("claude-haiku") == 100
    end
  end

  describe "cap_for/1" do
    test "derives cap = window * (1 - reserve) * chars_per_token" do
      # defaults: reserve_fraction 0.2, chars_per_token 3.5
      assert ContextWindow.cap_for(nil) == round(200_000 * 0.8 * 3.5)
      assert ContextWindow.cap_for("claude-cli") == round(1_000_000 * 0.8 * 3.5)
    end

    test "a larger context window yields a larger cap" do
      assert ContextWindow.cap_for("claude-cli") > ContextWindow.cap_for(nil)
    end

    test "honours config overrides for every knob" do
      put_cfg(default_window: 10_000, reserve_fraction: 0.5, chars_per_token: 4.0)
      assert ContextWindow.cap_for(nil) == round(10_000 * 0.5 * 4.0)
    end
  end
end
