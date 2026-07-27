defmodule Arcada.SubscriptionsTest do
  use Arcada.DataCase, async: true

  import Arcada.AccountsFixtures
  import Arcada.SubscriptionsFixtures

  alias Arcada.Subscriptions
  alias Arcada.Subscriptions.Subscription

  describe "create_subscription/2" do
    test "creates a query subscription" do
      user = user_fixture()

      assert {:ok, subscription} =
               Subscriptions.create_subscription(user, %{query: "renda", period: :semanal})

      assert subscription.query == "renda"
      assert subscription.period == :semanal
      assert subscription.active
      refute subscription.last_sent_at
    end

    test "a blank query is the digest, not an empty search" do
      user = user_fixture()

      assert {:ok, subscription} =
               Subscriptions.create_subscription(user, %{query: "   ", period: :mensal})

      assert subscription.query == nil
    end

    test "rejects a daily digest" do
      user = user_fixture()

      assert {:error, changeset} =
               Subscriptions.create_subscription(user, %{query: nil, period: :diaria})

      assert "o resumo de tudo não está disponível na frequência diária" in errors_on(changeset).period
    end

    test "allows a daily subscription when it has a query" do
      user = user_fixture()

      assert {:ok, _subscription} =
               Subscriptions.create_subscription(user, %{query: "greve", period: :diaria})
    end

    test "rejects a query carrying control characters" do
      user = user_fixture()

      assert {:error, changeset} =
               Subscriptions.create_subscription(user, %{
                 query: "renda\r\nBcc: alguem@exemplo.pt",
                 period: :semanal
               })

      assert "não pode conter quebras de linha" in errors_on(changeset).query
    end

    test "rejects a duplicate query + period" do
      user = user_fixture()
      subscription_fixture(user, %{query: "renda", period: :semanal})

      assert {:error, changeset} =
               Subscriptions.create_subscription(user, %{query: "renda", period: :semanal})

      assert "já tem uma subscrição igual" in errors_on(changeset).query
    end

    test "rejects a second digest at the same period" do
      user = user_fixture()
      subscription_fixture(user, %{query: nil, period: :semanal})

      assert {:error, changeset} =
               Subscriptions.create_subscription(user, %{query: nil, period: :semanal})

      assert "já tem um resumo com esta frequência" in errors_on(changeset).period
    end

    test "another user may hold the same subscription" do
      subscription_fixture(user_fixture(), %{query: "renda", period: :semanal})

      assert {:ok, _subscription} =
               Subscriptions.create_subscription(user_fixture(), %{
                 query: "renda",
                 period: :semanal
               })
    end

    test "caps how many one account can hold" do
      user = user_fixture()

      for n <- 1..Subscriptions.max_per_user() do
        subscription_fixture(user, %{query: "tema #{n}", period: :semanal})
      end

      assert {:error, changeset} =
               Subscriptions.create_subscription(user, %{query: "mais um", period: :semanal})

      assert ["atingiu o limite de #{Subscriptions.max_per_user()} subscrições"] ==
               errors_on(changeset).query
    end
  end

  describe "get_user_subscription!/2" do
    test "refuses to hand over someone else's subscription" do
      subscription = subscription_fixture(user_fixture())

      assert_raise Ecto.NoResultsError, fn ->
        Subscriptions.get_user_subscription!(user_fixture(), subscription.id)
      end
    end
  end

  describe "due?/2" do
    test "a subscription that has never run is due" do
      assert Subscriptions.due?(%Subscription{active: true, last_sent_at: nil, period: :mensal})
    end

    test "a paused subscription is never due" do
      refute Subscriptions.due?(%Subscription{active: false, last_sent_at: nil, period: :diaria})
    end

    test "becomes due once a full period has passed" do
      user = user_fixture()
      subscription = subscription_fixture(user, %{query: "renda", period: :semanal})
      today = ~D[2026-07-27]

      refute subscription |> with_last_sent(~D[2026-07-22]) |> Subscriptions.due?(today)
      assert subscription |> with_last_sent(~D[2026-07-20]) |> Subscriptions.due?(today)
    end
  end

  describe "window/2" do
    test "a first run covers one period ending today" do
      user = user_fixture()
      subscription = subscription_fixture(user, %{query: "renda", period: :semanal})

      assert Subscriptions.window(subscription, ~D[2026-07-27]) ==
               {~D[2026-07-21], ~D[2026-07-27]}
    end

    test "later runs start the day after the last one, so nothing is mailed twice" do
      user = user_fixture()

      subscription =
        user
        |> subscription_fixture(%{query: "renda", period: :semanal})
        |> with_last_sent(~D[2026-07-20])

      assert Subscriptions.window(subscription, ~D[2026-07-27]) ==
               {~D[2026-07-21], ~D[2026-07-27]}
    end

    test "clamps the catch-up window of a long-dormant subscription" do
      user = user_fixture()

      subscription =
        user
        |> subscription_fixture(%{query: "renda", period: :semanal})
        |> with_last_sent(~D[2025-01-01])

      assert {from, ~D[2026-07-27]} = Subscriptions.window(subscription, ~D[2026-07-27])
      assert Date.diff(~D[2026-07-27], from) == 21
    end
  end

  describe "due_subscriptions/2" do
    test "returns due, active subscriptions of confirmed users only" do
      today = ~D[2026-07-27]

      due = subscription_fixture(user_fixture(), %{query: "due", period: :semanal})

      _not_due =
        user_fixture()
        |> subscription_fixture(%{query: "recente", period: :semanal})
        |> with_last_sent(~D[2026-07-26])

      {:ok, _paused} =
        user_fixture()
        |> subscription_fixture(%{query: "pausada", period: :semanal})
        |> Subscriptions.set_active(false)

      _unconfirmed =
        subscription_fixture(unconfirmed_user_fixture(), %{
          query: "nao-confirmado",
          period: :semanal
        })

      assert [%Subscription{id: id}] = Subscriptions.due_subscriptions(10, today)
      assert id == due.id
    end

    test "caps the batch, oldest clock first" do
      today = ~D[2026-07-27]

      oldest =
        user_fixture()
        |> subscription_fixture(%{query: "antiga", period: :semanal})
        |> with_last_sent(~D[2026-06-01])

      _newer =
        user_fixture()
        |> subscription_fixture(%{query: "recente", period: :semanal})
        |> with_last_sent(~D[2026-07-10])

      assert [%Subscription{id: id}] = Subscriptions.due_subscriptions(1, today)
      assert id == oldest.id
    end

    test "preloads the owner so delivery needs no second query" do
      user = user_fixture()
      subscription_fixture(user, %{query: "renda", period: :semanal})

      assert [%Subscription{user: owner}] = Subscriptions.due_subscriptions(10)
      assert owner.id == user.id
    end
  end

  describe "unsubscribe tokens" do
    test "round-trips to the subscription" do
      subscription = subscription_fixture(user_fixture())
      token = Subscriptions.unsubscribe_token(subscription)

      assert {:ok, found} = Subscriptions.fetch_by_unsubscribe_token(token)
      assert found.id == subscription.id
    end

    test "rejects a forged token" do
      assert :error = Subscriptions.fetch_by_unsubscribe_token("nao-e-um-token")
    end

    test "rejects a token whose subscription is gone" do
      subscription = subscription_fixture(user_fixture())
      token = Subscriptions.unsubscribe_token(subscription)
      {:ok, _subscription} = Subscriptions.delete_subscription(subscription)

      assert :error = Subscriptions.fetch_by_unsubscribe_token(token)
    end
  end

  describe "mark_sent/2" do
    test "advances the cadence clock" do
      subscription = subscription_fixture(user_fixture())

      assert {:ok, %Subscription{last_sent_at: %DateTime{}}} =
               Subscriptions.mark_sent(subscription)
    end
  end
end
