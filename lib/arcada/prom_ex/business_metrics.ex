defmodule Arcada.PromEx.BusinessMetrics do
  @moduledoc """
  Prometheus gauges for the product itself (issue #98): how many users, how many
  subscriptions, how much of the register we have ingested and summarized, and
  how stale the newest act is. Drives the `arcada-business` dashboard.

  Polling, not events, because these are stock levels — how many rows exist right
  now — not flows. `SearchMetrics` is the event counterpart; keep the two
  patterns unmixed.

  The metric names, tags and poll groups are frozen in `docs/OBSERVABILITY.md` §2.
  Dashboards query those strings; `business_metrics_test.exs` asserts them.
  """

  use PromEx.Plugin

  import Ecto.Query

  require Logger

  alias Arcada.Accounts.User
  alias Arcada.Register
  alias Arcada.Register.{Act, Edition, Summary}
  alias Arcada.Repo
  alias Arcada.Subscriptions.Subscription

  @fast_poll_rate 60_000
  @slow_poll_rate 300_000

  @users_event [:arcada, :business, :users, :count]
  @subscribers_event [:arcada, :business, :subscribers, :count]
  @subscriptions_event [:arcada, :business, :subscriptions, :count]
  @acts_event [:arcada, :business, :acts, :count]
  @acts_by_tipo_event [:arcada, :business, :acts, :by_tipo, :count]
  @acts_by_domain_event [:arcada, :business, :acts, :by_domain, :count]
  @editions_event [:arcada, :business, :editions, :count]
  @register_lag_event [:arcada, :business, :register, :lag_days]
  @summaries_event [:arcada, :business, :summaries, :count]
  @summaries_cost_event [:arcada, :business, :summaries, :cost_usd]
  @summaries_tokens_event [:arcada, :business, :summaries, :tokens]

  # `tipo` is free text scraped from DRE, so it is an UNBOUNDED Prometheus tag —
  # anything off this list MUST fold into "outro" or the series count grows
  # forever. Derived from the prod distribution; ~20 values is the hard cap.
  @tipos [
    "Portaria",
    "Resolução do Conselho de Ministros",
    "Resolução da Assembleia da República",
    "Decreto-Lei",
    "Decreto do Presidente da República",
    "Aviso",
    "Lei",
    "Lei Orgânica",
    "Decreto",
    "Decreto Regulamentar",
    "Decreto Regulamentar Regional",
    "Decreto Legislativo Regional",
    "Declaração",
    "Declaração de Retificação",
    "Resolução da Assembleia Legislativa da Região Autónoma da Madeira",
    "Resolução da Assembleia Legislativa da Região Autónoma dos Açores",
    "Acórdão do Tribunal Constitucional",
    "Acórdão do Supremo Tribunal de Justiça",
    "Acórdão do Supremo Tribunal Administrativo"
  ]

  @tipo_lookup Map.new(@tipos, fn tipo -> {String.downcase(tipo), tipo} end)
  @other_tipo "outro"

  @cost_sources ~w(api subscription)
  @unknown_cost_source "unknown"

  @doc "The bucketed `tipo` tag values, plus `outro`."
  def tipos, do: @tipos ++ [@other_tipo]

  @impl true
  def polling_metrics(opts) do
    [
      fast_metrics(Keyword.get(opts, :fast_poll_rate, @fast_poll_rate)),
      slow_metrics(Keyword.get(opts, :slow_poll_rate, @slow_poll_rate))
    ]
  end

  defp fast_metrics(poll_rate) do
    Polling.build(
      :arcada_business_fast,
      poll_rate,
      {__MODULE__, :execute_fast_metrics, []},
      [
        last_value(@users_event,
          event_name: @users_event,
          measurement: :count,
          description: "Registered users, by email confirmation state.",
          tags: [:state]
        ),
        last_value(@subscribers_event,
          event_name: @subscribers_event,
          measurement: :count,
          description: "Distinct users holding at least one subscription."
        ),
        last_value(@subscriptions_event,
          event_name: @subscriptions_event,
          measurement: :count,
          description: "Subscriptions, by cadence, kind (tema/digest) and active flag.",
          tags: [:period, :kind, :active]
        )
      ]
    )
  end

  defp slow_metrics(poll_rate) do
    Polling.build(
      :arcada_business_slow,
      poll_rate,
      {__MODULE__, :execute_slow_metrics, []},
      [
        last_value(@acts_event,
          event_name: @acts_event,
          measurement: :count,
          description: "Acts ingested, split by whether a summary is published.",
          tags: [:summarized]
        ),
        last_value(@acts_by_tipo_event,
          event_name: @acts_by_tipo_event,
          measurement: :count,
          description: "Acts by diploma type, bucketed to a fixed allowlist.",
          tags: [:tipo]
        ),
        last_value(@acts_by_domain_event,
          event_name: @acts_by_domain_event,
          measurement: :count,
          description: "Published acts per life-domain, from the published summary.",
          tags: [:domain]
        ),
        last_value(@editions_event,
          event_name: @editions_event,
          measurement: :count,
          description: "Editions scraped."
        ),
        last_value(@register_lag_event,
          event_name: @register_lag_event,
          measurement: :lag_days,
          description: "Days between today and the newest act's published_at."
        ),
        last_value(@summaries_event,
          event_name: @summaries_event,
          measurement: :count,
          description: "Summaries generated."
        ),
        last_value(@summaries_cost_event,
          event_name: @summaries_cost_event,
          measurement: :cost_usd,
          description: "Cumulative LLM spend in USD, by cost source.",
          tags: [:cost_source]
        ),
        last_value(@summaries_tokens_event,
          event_name: @summaries_tokens_event,
          measurement: :tokens,
          description: "Cumulative LLM tokens, by direction.",
          tags: [:direction]
        )
      ]
    )
  end

  @doc false
  def execute_fast_metrics do
    if repo_running?() do
      safely(:users, &emit_users/0)
      safely(:subscribers, &emit_subscribers/0)
      safely(:subscriptions, &emit_subscriptions/0)
    end

    :ok
  end

  @doc false
  def execute_slow_metrics do
    if repo_running?() do
      safely(:acts, &emit_acts/0)
      safely(:acts_by_tipo, &emit_acts_by_tipo/0)
      safely(:acts_by_domain, &emit_acts_by_domain/0)
      safely(:editions, &emit_editions/0)
      safely(:register_lag, &emit_register_lag/0)
      safely(:summaries, &emit_summaries/0)
      safely(:summaries_cost, &emit_summaries_cost/0)
    end

    :ok
  end

  # Arcada.Application starts PromEx before Repo, so the first poll tick fires
  # with no Repo. Without this the boot log carries a warning per metric family.
  defp repo_running?, do: Repo in Ecto.Repo.all_running()

  # A measurement MFA that raises is filtered out of the telemetry_poller's
  # measurement list permanently (see telemetry_poller's
  # make_measurements_and_filter_misbehaving/1) — the metric never returns until
  # the node restarts. Nothing emitted beats a zero, which reads as real data.
  defp safely(family, fun) do
    fun.()
  rescue
    error ->
      Logger.warning("business metrics #{family} poll failed: #{Exception.message(error)}")
      :error
  catch
    kind, reason ->
      Logger.warning("business metrics #{family} poll #{kind}: #{inspect(reason)}")
      :error
  end

  defp emit_users do
    counts =
      Repo.all(
        from u in User,
          group_by: fragment("? IS NOT NULL", u.confirmed_at),
          select: {fragment("? IS NOT NULL", u.confirmed_at), count(u.id)}
      )
      |> Map.new(fn {confirmed?, count} ->
        {if(confirmed?, do: :confirmed, else: :unconfirmed), count}
      end)

    # Zero-fill: a gauge that stops being emitted keeps reporting its last value
    # forever, so a category emptying out would freeze at its old count.
    for state <- [:confirmed, :unconfirmed] do
      :telemetry.execute(@users_event, %{count: Map.get(counts, state, 0)}, %{state: state})
    end
  end

  defp emit_subscribers do
    count = Repo.one(from s in Subscription, select: count(s.user_id, :distinct))

    :telemetry.execute(@subscribers_event, %{count: count || 0}, %{})
  end

  defp emit_subscriptions do
    counts =
      Repo.all(
        from s in Subscription,
          group_by: [s.period, s.active, fragment("? IS NULL", s.query)],
          select: {s.period, s.active, fragment("? IS NULL", s.query), count(s.id)}
      )
      |> Map.new(fn {period, active, digest?, count} ->
        {{period, if(digest?, do: :digest, else: :tema), active}, count}
      end)

    for {kind, periods} <- [
          tema: Subscription.periods(),
          digest: Subscription.digest_periods()
        ],
        period <- periods,
        active <- [true, false] do
      :telemetry.execute(
        @subscriptions_event,
        %{count: Map.get(counts, {period, kind, active}, 0)},
        %{period: period, kind: kind, active: active}
      )
    end
  end

  defp emit_acts do
    counts =
      Repo.all(
        from a in Act,
          group_by: fragment("? IS NOT NULL", a.published_summary_id),
          select: {fragment("? IS NOT NULL", a.published_summary_id), count(a.id)}
      )
      |> Map.new()

    for summarized <- [true, false] do
      :telemetry.execute(
        @acts_event,
        %{count: Map.get(counts, summarized, 0)},
        %{summarized: summarized}
      )
    end
  end

  defp emit_acts_by_tipo do
    Repo.all(from a in Act, group_by: a.tipo, select: {a.tipo, count(a.id)})
    |> Enum.reduce(%{}, fn {tipo, count}, acc ->
      Map.update(acc, bucket_tipo(tipo), count, &(&1 + count))
    end)
    |> Enum.each(fn {tipo, count} ->
      :telemetry.execute(@acts_by_tipo_event, %{count: count}, %{tipo: tipo})
    end)
  end

  defp bucket_tipo(tipo) when is_binary(tipo) do
    Map.get(@tipo_lookup, tipo |> String.trim() |> String.downcase(), @other_tipo)
  end

  defp bucket_tipo(_), do: @other_tipo

  defp emit_acts_by_domain do
    counts =
      Repo.all(
        from a in Act,
          join: s in Summary,
          on: s.id == a.published_summary_id,
          group_by: fragment("unnest(?)", s.domains),
          select: {fragment("unnest(?)", s.domains), count(a.id, :distinct)}
      )
      |> Map.new()

    for domain <- Register.life_domains() do
      :telemetry.execute(
        @acts_by_domain_event,
        %{count: Map.get(counts, domain, 0)},
        %{domain: domain}
      )
    end
  end

  defp emit_editions do
    :telemetry.execute(@editions_event, %{count: Repo.aggregate(Edition, :count)}, %{})
  end

  defp emit_register_lag do
    case Repo.one(from a in Act, select: max(a.published_at)) do
      nil ->
        # No acts at all: emitting 0 would read as "perfectly fresh".
        :ok

      %Date{} = newest ->
        :telemetry.execute(
          @register_lag_event,
          %{lag_days: Date.diff(Date.utc_today(), newest)},
          %{}
        )
    end
  end

  defp emit_summaries do
    {count, input, output} =
      Repo.one(
        from s in Summary,
          select: {count(s.id), sum(s.input_tokens), sum(s.output_tokens)}
      )

    :telemetry.execute(@summaries_event, %{count: count}, %{})
    :telemetry.execute(@summaries_tokens_event, %{tokens: input || 0}, %{direction: :input})
    :telemetry.execute(@summaries_tokens_event, %{tokens: output || 0}, %{direction: :output})
  end

  defp emit_summaries_cost do
    Repo.all(
      from s in Summary,
        group_by: s.cost_source,
        select: {s.cost_source, sum(s.cost_usd)}
    )
    |> Enum.reduce(%{}, fn {source, total}, acc ->
      Map.update(acc, bucket_cost_source(source), to_usd(total), &(&1 + to_usd(total)))
    end)
    |> Enum.each(fn {source, total} ->
      :telemetry.execute(@summaries_cost_event, %{cost_usd: total}, %{cost_source: source})
    end)
  end

  defp bucket_cost_source(source) when source in @cost_sources, do: source
  defp bucket_cost_source(_), do: @unknown_cost_source

  # cost_usd is a nullable Decimal; PromEx exports a nil measurement as garbage.
  defp to_usd(nil), do: 0.0
  defp to_usd(%Decimal{} = value), do: Decimal.to_float(value)
end
