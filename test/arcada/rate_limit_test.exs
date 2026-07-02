defmodule Arcada.RateLimitTest do
  @moduledoc """
  Semantic-search rate limiting (issue #32). `async: false` — the limiter is a
  process-wide ETS singleton started in the supervision tree; each test uses a
  unique identity key so buckets never collide across tests.
  """
  use ExUnit.Case, async: false

  alias Arcada.RateLimit

  defp unique_anon, do: {:anon, "visitor-#{System.unique_integer([:positive])}"}
  defp unique_user, do: {:user, System.unique_integer([:positive])}

  test "allows up to the per-minute limit, then denies with a retry hint" do
    id = unique_anon()

    assert :ok = RateLimit.search_semantic(id, per_minute: 2, per_day: 100)
    assert :ok = RateLimit.search_semantic(id, per_minute: 2, per_day: 100)

    assert {:deny, retry_ms} = RateLimit.search_semantic(id, per_minute: 2, per_day: 100)
    assert is_integer(retry_ms) and retry_ms > 0
  end

  test "the per-day window denies even when the minute window has room" do
    id = unique_anon()

    assert :ok = RateLimit.search_semantic(id, per_minute: 100, per_day: 1)
    assert {:deny, _} = RateLimit.search_semantic(id, per_minute: 100, per_day: 1)
  end

  test "buckets are independent per identity" do
    a = unique_anon()
    b = unique_anon()

    # Exhaust a's minute budget…
    assert :ok = RateLimit.search_semantic(a, per_minute: 1, per_day: 100)
    assert {:deny, _} = RateLimit.search_semantic(a, per_minute: 1, per_day: 100)
    # …b is a different bucket, untouched.
    assert :ok = RateLimit.search_semantic(b, per_minute: 1, per_day: 100)
  end

  test "anon and user tiers are separate buckets" do
    anon = unique_anon()
    user = unique_user()

    assert :ok = RateLimit.search_semantic(anon, per_minute: 1, per_day: 100)
    assert {:deny, _} = RateLimit.search_semantic(anon, per_minute: 1, per_day: 100)
    # A user key with the same numeric id space is a different bucket.
    assert :ok = RateLimit.search_semantic(user, per_minute: 1, per_day: 100)
  end

  describe "limits_for/2" do
    test "falls back to built-in defaults" do
      assert Keyword.has_key?(RateLimit.limits_for(:anon), :per_minute)
      assert Keyword.has_key?(RateLimit.limits_for(:user), :per_day)
    end

    test "user tier is more generous than anon" do
      assert RateLimit.limits_for(:user)[:per_day] > RateLimit.limits_for(:anon)[:per_day]
    end

    test "explicit opts win over config and defaults" do
      assert RateLimit.limits_for(:anon, per_minute: 999)[:per_minute] == 999
    end
  end
end
