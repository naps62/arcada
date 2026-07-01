defmodule OQueMudou.RegisterQueryTest do
  use OQueMudou.DataCase, async: true

  alias OQueMudou.Repo
  alias OQueMudou.Register
  alias OQueMudou.Register.{Edition, Act, Summary}

  defp edition(date \\ ~D[2026-06-24]) do
    %Edition{}
    |> Edition.changeset(%{serie: "I", number: "ed-#{date}", date: date})
    |> Repo.insert!()
  end

  defp act(ed, dre_id, published_at) do
    %Act{}
    |> Act.changeset(%{edition_id: ed.id, dre_id: dre_id, published_at: published_at})
    |> Repo.insert!()
  end

  defp summarize(act, domains) do
    %Summary{}
    |> Summary.changeset(%{act_id: act.id, plain_text: "...", domains: domains})
    |> Repo.insert!()
  end

  describe "fetch_domain/1" do
    test "accepts taxonomy members (atom or string)" do
      assert Register.fetch_domain("fiscal") == {:ok, :fiscal}
      assert Register.fetch_domain(:habitação) == {:ok, :habitação}
    end

    test "rejects non-members" do
      assert Register.fetch_domain("cripto") == :error
      assert Register.fetch_domain(:nope) == :error
    end
  end

  describe "domain_counts/0" do
    test "returns the full taxonomy with per-domain act counts" do
      ed = edition()
      summarize(act(ed, "1", ~D[2026-06-24]), [:fiscal, :trabalho])
      summarize(act(ed, "2", ~D[2026-06-24]), [:fiscal])

      counts = Register.domain_counts()

      assert counts["fiscal"] == 2
      assert counts["trabalho"] == 1
      assert counts["saúde"] == 0
      # every taxonomy entry is present
      assert MapSet.new(Map.keys(counts)) == MapSet.new(Register.life_domains())
    end
  end

  describe "fetch_period/1" do
    test "accepts the fixed set (atom or string), nil otherwise" do
      assert Register.fetch_period("semana") == :semana
      assert Register.fetch_period(:mes) == :mes
      assert Register.fetch_period(nil) == nil
      assert Register.fetch_period("decada") == nil
    end
  end

  describe "period_counts/1" do
    setup do
      recent = edition(Date.utc_today())
      old = edition(~D[2000-01-01])
      summarize(act(recent, "r", Date.utc_today()), [:fiscal])
      summarize(act(old, "o", ~D[2000-01-01]), [:fiscal, :trabalho])
      :ok
    end

    test "buckets acts by window, with :tudo over all time" do
      counts = Register.period_counts()
      assert counts[:tudo] == 2
      assert counts[:ano] == 1
      assert counts[:mes] == 1
      assert counts[:semana] == 1
    end

    test "respects an active domain (the mirror of domain_counts)" do
      # trabalho only tags the old act → present in :tudo, absent from this year.
      counts = Register.period_counts(domain: :trabalho)
      assert counts[:tudo] == 1
      assert counts[:ano] == 0
      assert counts[:semana] == 0
    end
  end

  describe "domain_counts/1 with :period" do
    test "restricts the per-domain counts to the window" do
      recent = edition(Date.utc_today())
      old = edition(~D[2000-01-01])
      summarize(act(recent, "r", Date.utc_today()), [:fiscal])
      summarize(act(old, "o", ~D[2000-01-01]), [:fiscal, :trabalho])

      all = Register.domain_counts()
      assert all["fiscal"] == 2
      assert all["trabalho"] == 1

      this_year = Register.domain_counts(period: :ano)
      assert this_year["fiscal"] == 1
      assert this_year["trabalho"] == 0
    end
  end

  describe "list_acts/1 with :period" do
    test "keeps only acts inside the window" do
      recent = edition(Date.utc_today())
      old = edition(~D[2000-01-01])
      a_recent = act(recent, "r", Date.utc_today())
      act(old, "o", ~D[2000-01-01])

      assert [act] = Register.list_acts(period: :semana)
      assert act.id == a_recent.id

      assert length(Register.list_acts(period: :ano)) == 1
      assert length(Register.list_acts()) == 2
    end
  end

  describe "list_acts/1" do
    setup do
      ed = edition()
      a1 = act(ed, "1", ~D[2026-06-22])
      a2 = act(ed, "2", ~D[2026-06-24])
      summarize(a1, [:fiscal])
      summarize(a2, [:trabalho, :saúde])
      %{a1: a1, a2: a2}
    end

    test "returns all acts newest-first by default", %{a1: a1, a2: a2} do
      ids = Register.list_acts() |> Enum.map(& &1.id)
      assert ids == [a2.id, a1.id]
    end

    test "filters by domain", %{a1: a1, a2: a2} do
      assert [act] = Register.list_acts(domain: :fiscal)
      assert act.id == a1.id

      assert [act2] = Register.list_acts(domain: "saúde")
      assert act2.id == a2.id
    end

    test "unknown domain matches nothing" do
      assert Register.list_acts(domain: "cripto") == []
    end

    test "respects :limit", %{a2: a2} do
      assert [act] = Register.list_acts(limit: 1)
      assert act.id == a2.id
    end

    test "preloads edition and summaries", %{} do
      [act | _] = Register.list_acts()
      assert %Edition{} = act.edition
      assert [%Summary{} | _] = act.summaries
    end
  end

  describe "list_acts_by_day/1" do
    # One act on each of three consecutive days.
    defp three_days do
      for d <- 1..3 do
        date = Date.new!(2026, 6, d)
        act(edition(date), "a-#{d}", date)
      end
    end

    test "returns days newest-first, grouped, capping the page and flagging more" do
      three_days()

      {groups, more?} = Register.list_acts_by_day(days: 2)

      assert more?
      assert Enum.map(groups, &elem(&1, 0)) == [~D[2026-06-03], ~D[2026-06-02]]
    end

    test "the :before cursor pages to strictly older days, exhausting the list" do
      three_days()

      {groups, more?} = Register.list_acts_by_day(days: 2, before: ~D[2026-06-02])

      refute more?
      assert Enum.map(groups, &elem(&1, 0)) == [~D[2026-06-01]]
    end

    test "keeps a day's acts whole — a day is never split across the boundary" do
      date = ~D[2026-06-10]
      ed = edition(date)
      for i <- 1..3, do: act(ed, "x-#{i}", date)

      {groups, more?} = Register.list_acts_by_day(days: 5)

      refute more?
      assert [{^date, acts}] = groups
      assert length(acts) == 3
    end

    test "filters by domain and preloads" do
      date = ~D[2026-06-24]
      ed = edition(date)
      summarize(act(ed, "f", date), [:fiscal])
      summarize(act(ed, "t", date), [:trabalho])

      {groups, _more?} = Register.list_acts_by_day(domain: "fiscal")

      assert [{^date, [act]}] = groups
      assert act.dre_id == "f"
      assert %Edition{} = act.edition
      assert [%Summary{} | _] = act.summaries
    end

    test "empty listing returns no groups and no more pages" do
      assert Register.list_acts_by_day() == {[], false}
    end
  end
end
