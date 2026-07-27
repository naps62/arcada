defmodule Arcada.Subscriptions.MatcherTest do
  use Arcada.DataCase, async: false

  import Arcada.AccountsFixtures
  import Arcada.RegisterFixtures
  import Arcada.SubscriptionsFixtures

  alias Arcada.Search.Index
  alias Arcada.Subscriptions.Matcher
  alias Arcada.Summarizer.Embeddings

  setup do
    Index.clear()
    :ok
  end

  defp set_embeddings(kw) do
    prev = Application.get_env(:arcada, Embeddings, [])
    Application.put_env(:arcada, Embeddings, kw)
    on_exit(fn -> Application.put_env(:arcada, Embeddings, prev) end)
  end

  # `Index`'s query→embedding cache outlives a single test, so each test embeds
  # under its own query text.
  defp unique_query, do: "assunto-#{System.unique_integer([:positive])}"

  describe "digest subscriptions" do
    test "list everything published in the window, newest first" do
      user = user_fixture()
      subscription = subscription_fixture(user, %{query: nil, period: :semanal})

      older = act_fixture(%{published_at: ~D[2026-07-21]})
      newer = act_fixture(%{published_at: ~D[2026-07-24]})
      _outside = act_fixture(%{published_at: ~D[2026-07-19]})

      ids =
        subscription
        |> Matcher.matches({~D[2026-07-20], ~D[2026-07-27]})
        |> Enum.map(& &1.id)

      assert ids == [newer.id, older.id]
    end

    test "an empty window means no email" do
      user = user_fixture()
      subscription = subscription_fixture(user, %{query: nil, period: :semanal})
      act_fixture(%{published_at: ~D[2026-01-01]})

      assert Matcher.matches(subscription, {~D[2026-07-20], ~D[2026-07-27]}) == []
    end
  end

  describe "query subscriptions" do
    test "find a strong semantic match inside the window" do
      query = unique_query()
      set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

      user = user_fixture()
      subscription = subscription_fixture(user, %{query: query, period: :semanal})

      hit = act_fixture(%{published_at: ~D[2026-07-24]})
      summary_fixture(hit, %{embedding: [1.0, 0.0]})

      assert [%{id: id}] = Matcher.matches(subscription, {~D[2026-07-20], ~D[2026-07-27]})
      assert id == hit.id
    end

    test "ignore a strong match published outside the window" do
      query = unique_query()
      set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

      user = user_fixture()
      subscription = subscription_fixture(user, %{query: query, period: :semanal})

      old_hit = act_fixture(%{published_at: ~D[2026-05-01]})
      summary_fixture(old_hit, %{embedding: [1.0, 0.0]})

      assert Matcher.matches(subscription, {~D[2026-07-20], ~D[2026-07-27]}) == []
    end

    # The point of the absolute floor: a week whose best act is only vaguely
    # related must produce no email at all, not "here's the best of a bad lot".
    test "a weak best-in-window match is not worth an email" do
      query = unique_query()
      set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

      user = user_fixture()
      subscription = subscription_fixture(user, %{query: query, period: :semanal})

      weak = act_fixture(%{published_at: ~D[2026-07-24]})
      summary_fixture(weak, %{plain_text: "algo sem relação", embedding: [0.2, 0.98]})

      assert Matcher.matches(subscription, {~D[2026-07-20], ~D[2026-07-27]}) == []
    end
  end
end
