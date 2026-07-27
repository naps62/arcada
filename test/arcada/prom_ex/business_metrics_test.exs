defmodule Arcada.PromEx.BusinessMetricsTest do
  use Arcada.DataCase, async: true

  import ExUnit.CaptureLog

  import Arcada.AccountsFixtures
  import Arcada.RegisterFixtures
  import Arcada.SubscriptionsFixtures

  alias Arcada.PromEx.BusinessMetrics

  @fast_events [
    [:arcada, :business, :users, :count],
    [:arcada, :business, :subscribers, :count],
    [:arcada, :business, :subscriptions, :count]
  ]

  @slow_events [
    [:arcada, :business, :acts, :count],
    [:arcada, :business, :acts, :by_tipo, :count],
    [:arcada, :business, :acts, :by_domain, :count],
    [:arcada, :business, :editions, :count],
    [:arcada, :business, :register, :lag_days],
    [:arcada, :business, :summaries, :count],
    [:arcada, :business, :summaries, :cost_usd],
    [:arcada, :business, :summaries, :tokens]
  ]

  defp attach(events) do
    :telemetry_test.attach_event_handlers(self(), events)
  end

  # Every event emitted by one poll run, as `{event, measurements, metadata}`.
  defp drain do
    receive do
      {event, _ref, measurements, metadata} -> [{event, measurements, metadata} | drain()]
    after
      0 -> []
    end
  end

  defp measurement_for(emitted, event, metadata_match) do
    Enum.find_value(emitted, fn {name, measurements, metadata} ->
      if name == event and Enum.all?(metadata_match, fn {k, v} -> metadata[k] == v end) do
        measurements
      end
    end)
  end

  describe "polling_metrics/1" do
    test "builds the two contract poll groups at the documented rates" do
      assert [fast, slow] = BusinessMetrics.polling_metrics([])

      assert fast.group_name == :arcada_business_fast
      assert fast.poll_rate == 60_000
      assert fast.measurements_mfa == {BusinessMetrics, :execute_fast_metrics, []}

      assert slow.group_name == :arcada_business_slow
      assert slow.poll_rate == 300_000
      assert slow.measurements_mfa == {BusinessMetrics, :execute_slow_metrics, []}
    end

    test "poll rates are overridable via plugin opts" do
      assert [fast, slow] =
               BusinessMetrics.polling_metrics(fast_poll_rate: 1_000, slow_poll_rate: 2_000)

      assert fast.poll_rate == 1_000
      assert slow.poll_rate == 2_000
    end

    # docs/OBSERVABILITY.md §2 is the frozen contract; the business dashboard
    # queries these exact strings. PromEx joins the metric name with "_", so a
    # rename here silently breaks every panel.
    test "exports the Prometheus metric names frozen in docs/OBSERVABILITY.md" do
      names =
        BusinessMetrics.polling_metrics([])
        |> Enum.flat_map(& &1.metrics)
        |> Enum.map(&Enum.join(&1.name, "_"))

      assert names == [
               "arcada_business_users_count",
               "arcada_business_subscribers_count",
               "arcada_business_subscriptions_count",
               "arcada_business_acts_count",
               "arcada_business_acts_by_tipo_count",
               "arcada_business_acts_by_domain_count",
               "arcada_business_editions_count",
               "arcada_business_register_lag_days",
               "arcada_business_summaries_count",
               "arcada_business_summaries_cost_usd",
               "arcada_business_summaries_tokens"
             ]
    end

    test "tags stay within the documented bounded domains" do
      tags =
        BusinessMetrics.polling_metrics([])
        |> Enum.flat_map(& &1.metrics)
        |> Map.new(&{Enum.join(&1.name, "_"), &1.tags})

      assert tags["arcada_business_users_count"] == [:state]
      assert tags["arcada_business_subscribers_count"] == []
      assert tags["arcada_business_subscriptions_count"] == [:period, :kind, :active]
      assert tags["arcada_business_acts_count"] == [:summarized]
      assert tags["arcada_business_acts_by_tipo_count"] == [:tipo]
      assert tags["arcada_business_acts_by_domain_count"] == [:domain]
      assert tags["arcada_business_register_lag_days"] == []
      assert tags["arcada_business_summaries_cost_usd"] == [:cost_source]
      assert tags["arcada_business_summaries_tokens"] == [:direction]
    end

    test "the tipo allowlist stays inside the cardinality cap" do
      assert length(BusinessMetrics.tipos()) <= 20
      assert "outro" in BusinessMetrics.tipos()
    end
  end

  describe "execute_fast_metrics/0" do
    test "counts users by confirmation state" do
      user_fixture()
      user_fixture()
      unconfirmed_user_fixture()

      attach(@fast_events)
      assert :ok = BusinessMetrics.execute_fast_metrics()
      emitted = drain()

      event = [:arcada, :business, :users, :count]
      assert %{count: 2} = measurement_for(emitted, event, state: :confirmed)
      assert %{count: 1} = measurement_for(emitted, event, state: :unconfirmed)
    end

    test "counts distinct subscribers, not subscriptions" do
      user = user_fixture()
      subscription_fixture(user, query: "arrendamento", period: :semanal)
      subscription_fixture(user, query: "IRS", period: :mensal)

      attach(@fast_events)
      assert :ok = BusinessMetrics.execute_fast_metrics()

      assert %{count: 1} =
               measurement_for(drain(), [:arcada, :business, :subscribers, :count], [])
    end

    test "groups subscriptions by period, kind and active" do
      user = user_fixture()
      subscription_fixture(user, query: "arrendamento", period: :semanal)
      subscription_fixture(user, query: nil, period: :mensal)

      attach(@fast_events)
      assert :ok = BusinessMetrics.execute_fast_metrics()
      emitted = drain()

      event = [:arcada, :business, :subscriptions, :count]

      assert %{count: 1} =
               measurement_for(emitted, event, period: :semanal, kind: :tema, active: true)

      assert %{count: 1} =
               measurement_for(emitted, event, period: :mensal, kind: :digest, active: true)

      assert %{count: 0} =
               measurement_for(emitted, event, period: :semanal, kind: :tema, active: false)
    end

    test "never offers the digest cadence the DB forbids" do
      attach(@fast_events)
      assert :ok = BusinessMetrics.execute_fast_metrics()

      refute measurement_for(
               drain(),
               [:arcada, :business, :subscriptions, :count],
               period: :diaria,
               kind: :digest
             )
    end
  end

  describe "execute_slow_metrics/0" do
    test "splits acts by whether a summary is published" do
      edition = edition_fixture()
      act = act_fixture(edition: edition)
      summary = summary_fixture(act, domains: [:fiscal, :trabalho])
      Repo.update!(Ecto.Changeset.change(act, published_summary_id: summary.id))
      act_fixture(edition: edition)

      attach(@slow_events)
      assert :ok = BusinessMetrics.execute_slow_metrics()
      emitted = drain()

      event = [:arcada, :business, :acts, :count]
      assert %{count: 1} = measurement_for(emitted, event, summarized: true)
      assert %{count: 1} = measurement_for(emitted, event, summarized: false)
    end

    test "counts a published act once per life-domain, zero-filling the taxonomy" do
      act = act_fixture()
      summary = summary_fixture(act, domains: [:fiscal, :trabalho])
      Repo.update!(Ecto.Changeset.change(act, published_summary_id: summary.id))

      attach(@slow_events)
      assert :ok = BusinessMetrics.execute_slow_metrics()
      emitted = drain()

      event = [:arcada, :business, :acts, :by_domain, :count]
      assert %{count: 1} = measurement_for(emitted, event, domain: "fiscal")
      assert %{count: 1} = measurement_for(emitted, event, domain: "trabalho")
      assert %{count: 0} = measurement_for(emitted, event, domain: "saúde")
    end

    test "an unpublished summary's domains are not counted" do
      act = act_fixture()
      summary_fixture(act, domains: [:fiscal])

      attach(@slow_events)
      assert :ok = BusinessMetrics.execute_slow_metrics()

      assert %{count: 0} =
               measurement_for(
                 drain(),
                 [:arcada, :business, :acts, :by_domain, :count],
                 domain: "fiscal"
               )
    end

    test "buckets a known tipo verbatim and junk into outro" do
      act_fixture(tipo: "Decreto-Lei")
      act_fixture(tipo: "Regulamento Interno da Junta de Freguesia de Sítio Nenhum")
      act_fixture(tipo: nil)

      attach(@slow_events)
      assert :ok = BusinessMetrics.execute_slow_metrics()
      emitted = drain()

      event = [:arcada, :business, :acts, :by_tipo, :count]
      assert %{count: 1} = measurement_for(emitted, event, tipo: "Decreto-Lei")
      assert %{count: 2} = measurement_for(emitted, event, tipo: "outro")
    end

    test "counts editions and summaries" do
      edition = edition_fixture()
      act = act_fixture(edition: edition)
      summary_fixture(act)
      summary_fixture(act)

      attach(@slow_events)
      assert :ok = BusinessMetrics.execute_slow_metrics()
      emitted = drain()

      assert %{count: 1} = measurement_for(emitted, [:arcada, :business, :editions, :count], [])
      assert %{count: 2} = measurement_for(emitted, [:arcada, :business, :summaries, :count], [])
    end

    test "reports register lag in days from the newest act" do
      act_fixture(published_at: Date.add(Date.utc_today(), -3))
      act_fixture(published_at: Date.add(Date.utc_today(), -40))

      attach(@slow_events)
      assert :ok = BusinessMetrics.execute_slow_metrics()

      assert %{lag_days: 3} =
               measurement_for(drain(), [:arcada, :business, :register, :lag_days], [])
    end

    test "sums cost by source, folding nil into unknown and nil Decimals into 0.0" do
      act = act_fixture()
      summary_fixture(act, cost_usd: Decimal.new("0.25"), cost_source: "api")
      summary_fixture(act, cost_usd: Decimal.new("0.75"), cost_source: "api")
      summary_fixture(act, cost_usd: nil, cost_source: nil)

      attach(@slow_events)
      assert :ok = BusinessMetrics.execute_slow_metrics()
      emitted = drain()

      event = [:arcada, :business, :summaries, :cost_usd]
      assert %{cost_usd: 1.0} = measurement_for(emitted, event, cost_source: "api")
      assert %{cost_usd: +0.0} = measurement_for(emitted, event, cost_source: "unknown")
    end

    test "sums tokens by direction, treating nil as 0" do
      act = act_fixture()
      summary_fixture(act, input_tokens: 100, output_tokens: 20)
      summary_fixture(act, input_tokens: nil, output_tokens: nil)

      attach(@slow_events)
      assert :ok = BusinessMetrics.execute_slow_metrics()
      emitted = drain()

      event = [:arcada, :business, :summaries, :tokens]
      assert %{tokens: 100} = measurement_for(emitted, event, direction: :input)
      assert %{tokens: 20} = measurement_for(emitted, event, direction: :output)
    end

    test "no measurement is ever nil" do
      act = act_fixture()
      summary_fixture(act)

      attach(@slow_events ++ @fast_events)
      assert :ok = BusinessMetrics.execute_fast_metrics()
      assert :ok = BusinessMetrics.execute_slow_metrics()

      for {_event, measurements, _metadata} <- drain(),
          {_key, value} <- measurements do
        assert is_number(value)
      end
    end
  end

  describe "empty database" do
    test "emits zeroed gauges but no register lag" do
      attach(@fast_events ++ @slow_events)
      assert :ok = BusinessMetrics.execute_fast_metrics()
      assert :ok = BusinessMetrics.execute_slow_metrics()
      emitted = drain()

      assert %{count: 0} =
               measurement_for(emitted, [:arcada, :business, :users, :count], state: :confirmed)

      assert %{count: 0} = measurement_for(emitted, [:arcada, :business, :editions, :count], [])

      # 0 would read as "the register is perfectly fresh".
      refute measurement_for(emitted, [:arcada, :business, :register, :lag_days], [])
    end
  end

  describe "database failure" do
    test "both poll functions return normally and emit nothing" do
      attach(@fast_events ++ @slow_events)

      log =
        capture_log(fn ->
          assert :ok = without_db(&BusinessMetrics.execute_fast_metrics/0)
          assert :ok = without_db(&BusinessMetrics.execute_slow_metrics/0)
        end)

      assert drain() == []
      assert log =~ "business metrics"
      assert log =~ "poll failed"
    end
  end

  # Runs `fun` in a process the Ecto sandbox has never granted a connection to,
  # which is what the real poller looks like against a dead or migrating DB.
  # `spawn/1` on purpose: Task would propagate `$callers` and inherit ownership.
  defp without_db(fun) do
    parent = self()
    ref = make_ref()

    spawn(fn -> send(parent, {ref, fun.()}) end)

    receive do
      {^ref, result} -> result
    after
      5_000 -> flunk("poll function never returned")
    end
  end
end
