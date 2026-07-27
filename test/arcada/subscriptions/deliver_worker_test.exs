defmodule Arcada.Subscriptions.DeliverWorkerTest.RejectingAdapter do
  @moduledoc false
  @behaviour Swoosh.Adapter

  @impl true
  def deliver(_email, _config), do: {:error, {:tem, "quota exceeded"}}

  @impl true
  def validate_config(_config), do: :ok
end

defmodule Arcada.Subscriptions.DeliverWorkerTest.RaisingAdapter do
  @moduledoc false
  @behaviour Swoosh.Adapter

  @impl true
  def deliver(_email, _config), do: raise("connection reset")

  @impl true
  def validate_config(_config), do: :ok
end

defmodule Arcada.Subscriptions.DeliverWorkerTest do
  # async: false — a process-wide embeddings stub and the in-memory search index.
  use Arcada.DataCase, async: false
  use Oban.Testing, repo: Arcada.Repo

  import ExUnit.CaptureLog

  import Arcada.AccountsFixtures
  import Arcada.RegisterFixtures
  import Arcada.SubscriptionsFixtures
  import Swoosh.TestAssertions

  alias Arcada.PromEx.BusinessMetrics
  alias Arcada.Search.Index
  alias Arcada.Subscriptions
  alias Arcada.Subscriptions.DeliverWorker
  alias Arcada.Summarizer.Embeddings

  setup do
    Index.clear()
    prev = Application.get_env(:arcada, Embeddings, [])

    Application.put_env(:arcada, Embeddings,
      embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end
    )

    on_exit(fn -> Application.put_env(:arcada, Embeddings, prev) end)
    :ok
  end

  defp run(subscription), do: perform_job(DeliverWorker, %{subscription_id: subscription.id})

  defp reload(subscription), do: Subscriptions.get_subscription(subscription.id)

  defp act_in_window(attrs \\ %{}) do
    act_fixture(Map.put(Map.new(attrs), :published_at, Date.utc_today()))
  end

  test "mails the digest and advances the clock" do
    user = user_fixture()
    subscription = subscription_fixture(user, %{query: nil, period: :semanal})
    act_in_window(%{title: "Portaria n.º 1/2026"})

    assert :ok = run(subscription)

    assert_email_sent(fn email ->
      assert {_name, address} = hd(email.to)
      assert address == user.email
      assert email.subject =~ "resumo semanal"
      assert email.text_body =~ "Portaria n.º 1/2026"
      # Every bulk email carries a way out, in the body and in the headers.
      assert email.text_body =~ "/subscricoes/cancelar/"
      assert Map.has_key?(email.headers, "List-Unsubscribe")
    end)

    assert reload(subscription).last_sent_at
  end

  test "mails a query subscription only what matches" do
    user = user_fixture()
    subscription = subscription_fixture(user, %{query: "arrendamento", period: :semanal})

    hit = act_in_window(%{title: "Lei do arrendamento"})
    summary_fixture(hit, %{headline: "Novas regras para o arrendamento", embedding: [1.0, 0.0]})

    miss = act_in_window(%{title: "Outra coisa qualquer"})
    summary_fixture(miss, %{plain_text: "nada a ver", embedding: [0.2, 0.98]})

    assert :ok = run(subscription)

    assert_email_sent(fn email ->
      assert email.subject =~ "«arrendamento»"
      refute email.text_body =~ "Outra coisa qualquer"
      assert email.text_body =~ "Novas regras para o arrendamento"
    end)
  end

  # The clock has to move even on a silent run, or the window grows without
  # bound and the first real match arrives as a months-long email.
  test "a run with no matches sends nothing but still advances the clock" do
    user = user_fixture()
    subscription = subscription_fixture(user, %{query: "arrendamento", period: :semanal})

    assert :ok = run(subscription)

    assert_no_email_sent()
    assert reload(subscription).last_sent_at
  end

  test "skips a paused subscription" do
    user = user_fixture()
    subscription = subscription_fixture(user, %{query: nil, period: :semanal})
    {:ok, subscription} = Subscriptions.set_active(subscription, false)
    act_in_window()

    assert :ok = run(subscription)

    assert_no_email_sent()
    refute reload(subscription).last_sent_at
  end

  test "never mails an unconfirmed account" do
    user = unconfirmed_user_fixture()
    subscription = subscription_fixture(user, %{query: nil, period: :semanal})
    act_in_window()

    assert :ok = run(subscription)

    assert_no_email_sent()
  end

  test "tolerates a subscription deleted between dispatch and delivery" do
    subscription = subscription_fixture(user_fixture(), %{query: nil, period: :semanal})
    {:ok, _subscription} = Subscriptions.delete_subscription(subscription)

    assert :ok = run(subscription)
    assert_no_email_sent()
  end

  # arcada_business_emails_total is the contract's only flow metric: it is what
  # answers "did today's send actually go out". Taking the event name from the
  # plugin rather than a literal is the point — a drift between emitter and
  # metric definition would otherwise pass both files' own tests.
  describe "email counter (#98)" do
    setup do
      %{metrics: [emails]} = BusinessMetrics.event_metrics([])
      :telemetry_test.attach_event_handlers(self(), [emails.event_name])
      %{event: emails.event_name}
    end

    defp with_digest_adapter(adapter) do
      prev = Application.get_env(:arcada, Arcada.DigestMailer)
      Application.put_env(:arcada, Arcada.DigestMailer, adapter: adapter)
      on_exit(fn -> Application.put_env(:arcada, Arcada.DigestMailer, prev) end)
    end

    test "counts a delivered digest as sent", %{event: event} do
      subscription = subscription_fixture(user_fixture(), %{query: nil, period: :semanal})
      act_in_window()

      assert :ok = run(subscription)

      assert_receive {^event, _ref, %{count: 1}, %{kind: :digest, result: :sent}}
    end

    test "counts a rejected send as failed", %{event: event} do
      with_digest_adapter(Arcada.Subscriptions.DeliverWorkerTest.RejectingAdapter)

      subscription = subscription_fixture(user_fixture(), %{query: nil, period: :semanal})
      act_in_window()

      assert capture_log(fn ->
               assert {:error, _reason} = run(subscription)
             end) =~ "delivery failed"

      assert_receive {^event, _ref, %{count: 1}, %{kind: :digest, result: :failed}}
      # The clock must not advance on a failure, or the window is lost.
      refute reload(subscription).last_sent_at
    end

    test "counts a raising adapter as failed and still lets Oban retry", %{event: event} do
      with_digest_adapter(Arcada.Subscriptions.DeliverWorkerTest.RaisingAdapter)

      subscription = subscription_fixture(user_fixture(), %{query: nil, period: :semanal})
      act_in_window()

      assert_raise RuntimeError, "connection reset", fn -> run(subscription) end

      assert_receive {^event, _ref, %{count: 1}, %{kind: :digest, result: :failed}}
    end

    test "tags a topic subscription as tema", %{event: event} do
      subscription = subscription_fixture(user_fixture(), %{query: "arrendamento"})
      hit = act_in_window(%{title: "Lei do arrendamento"})
      summary_fixture(hit, %{headline: "Novas regras", embedding: [1.0, 0.0]})

      assert :ok = run(subscription)

      assert_receive {^event, _ref, %{count: 1}, %{kind: :tema, result: :sent}}
    end

    test "a run with no matches attempts nothing and counts nothing", %{event: event} do
      subscription = subscription_fixture(user_fixture(), %{query: "arrendamento"})

      assert :ok = run(subscription)

      refute_receive {^event, _ref, _measurements, _metadata}
    end
  end
end
