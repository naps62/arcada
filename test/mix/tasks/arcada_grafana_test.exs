defmodule Mix.Tasks.Arcada.GrafanaTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Arcada.Grafana

  @snapshots %{
    "oqm-overview" => 41,
    "arcada-business" => 31
  }

  describe "normalize/1" do
    test "strips per-instance noise and hoists the folder uid" do
      body = %{
        "meta" => %{
          "folderUid" => "o-que-mudou",
          "folderTitle" => "Arcada",
          "created" => "2026-07-01T00:00:00Z",
          "updated" => "2026-07-27T00:00:00Z",
          "url" => "/d/oqm-overview/arcada",
          "version" => 5
        },
        "dashboard" => %{
          "id" => 7,
          "uid" => "oqm-overview",
          "title" => "Arcada — App & Processing",
          "version" => 5,
          "panels" => []
        }
      }

      assert %{"folderUid" => "o-que-mudou", "dashboard" => dashboard} = Grafana.normalize(body)
      refute Map.has_key?(dashboard, "id")

      # version is the optimistic-concurrency token push relies on; dropping it
      # would disarm the guard.
      assert dashboard["version"] == 5
      assert dashboard["uid"] == "oqm-overview"
      assert dashboard["title"] == "Arcada — App & Processing"
    end

    test "a dashboard in General gets an empty folder uid, never nil" do
      assert %{"folderUid" => ""} =
               Grafana.normalize(%{"meta" => %{}, "dashboard" => %{"uid" => "x"}})
    end
  end

  describe "canonical_json/1" do
    test "sorts keys at every depth and ends with a newline" do
      json =
        Grafana.canonical_json(%{"b" => 1, "a" => %{"z" => [%{"n" => 1, "m" => 2}], "y" => 2}})

      assert String.ends_with?(json, "\n")
      assert json =~ "\n  "
      keys = Regex.scan(~r/"(\w)":/, json) |> Enum.map(fn [_, k] -> k end)
      assert keys == ~w(a y z m n b)
    end

    test "map key order in memory does not change the output" do
      one = Grafana.canonical_json(%{"a" => 1, "b" => 2, "c" => 3})
      other = Grafana.canonical_json(Map.new([{"c", 3}, {"b", 2}, {"a", 1}]))
      assert one == other
    end
  end

  describe "committed snapshots" do
    test "every file in priv/grafana is covered by these tests" do
      on_disk = "priv/grafana/*.json" |> Path.wildcard() |> Enum.map(&Path.basename(&1, ".json"))
      assert Enum.sort(on_disk) == Enum.sort(Map.keys(@snapshots))
    end

    for {uid, panel_count} <- @snapshots do
      @uid uid
      @panel_count panel_count
      @path "priv/grafana/#{uid}.json"

      test "#{uid} is already canonical, so a re-pull is a no-op diff" do
        raw = File.read!(@path)
        assert raw == Grafana.canonical_json(Jason.decode!(raw))
      end

      test "#{uid} keeps folder, uid and panels, and carries no per-instance noise" do
        doc = Grafana.read_doc!(@path)

        assert doc["folderUid"] == "o-que-mudou"
        refute Map.has_key?(doc, "meta")
        refute Map.has_key?(doc["dashboard"], "id")
        assert doc["dashboard"]["uid"] == @uid
        assert is_integer(doc["dashboard"]["version"])
        assert length(doc["dashboard"]["panels"]) == @panel_count
      end
    end
  end

  describe "read_doc!/1" do
    setup %{tmp_dir: tmp_dir}, do: %{dir: tmp_dir}

    @describetag :tmp_dir

    test "reads the wrapped form pull writes", %{dir: dir} do
      path = write(dir, "a.json", %{"folderUid" => "f", "dashboard" => %{"uid" => "a"}})

      assert %{"folderUid" => "f", "dashboard" => %{"uid" => "a"}} = Grafana.read_doc!(path)
    end

    test "refuses a bare dashboard object and says how to get a good one", %{dir: dir} do
      path = write(dir, "arcada-business.json", %{"uid" => "arcada-business", "panels" => []})

      assert_raise Mix.Error, ~r/mix arcada\.grafana pull arcada-business/, fn ->
        Grafana.read_doc!(path)
      end
    end

    test "refuses a wrapper with no folderUid", %{dir: dir} do
      path = write(dir, "b.json", %{"dashboard" => %{"uid" => "b"}})
      assert_raise Mix.Error, ~r/not in the expected shape/, fn -> Grafana.read_doc!(path) end
    end

    test "refuses JSON that is not a dashboard", %{dir: dir} do
      path = write(dir, "c.json", %{"nope" => true})
      assert_raise Mix.Error, ~r/not in the expected shape/, fn -> Grafana.read_doc!(path) end
    end

    test "refuses invalid JSON", %{dir: dir} do
      path = Path.join(dir, "d.json")
      File.write!(path, "{oops")
      assert_raise Mix.Error, ~r/invalid JSON/, fn -> Grafana.read_doc!(path) end
    end

    test "refuses a missing file", %{dir: dir} do
      assert_raise Mix.Error, ~r/no such dashboard file/, fn ->
        Grafana.read_doc!(Path.join(dir, "gone.json"))
      end
    end

    defp write(dir, name, data) do
      path = Path.join(dir, name)
      File.write!(path, Jason.encode!(data))
      path
    end
  end
end
