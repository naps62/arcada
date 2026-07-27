defmodule Mix.Tasks.Arcada.GrafanaTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Arcada.Grafana

  @snapshot "priv/grafana/oqm-overview.json"

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

  describe "the committed snapshot" do
    @describetag :tmp_dir

    test "is already canonical, so a re-pull is a no-op diff" do
      raw = File.read!(@snapshot)
      assert raw == Grafana.canonical_json(Jason.decode!(raw))
    end

    test "keeps the folder, the uid and the panels, and carries no per-instance noise" do
      doc = Jason.decode!(File.read!(@snapshot))

      assert doc["folderUid"] == "o-que-mudou"
      refute Map.has_key?(doc, "meta")
      refute Map.has_key?(doc["dashboard"], "id")
      assert doc["dashboard"]["uid"] == "oqm-overview"
      assert is_integer(doc["dashboard"]["version"])
      assert length(doc["dashboard"]["panels"]) == 41
    end
  end

  describe "read_doc!/1" do
    setup %{tmp_dir: tmp_dir}, do: %{dir: tmp_dir}

    @describetag :tmp_dir

    test "reads the wrapped form pull writes", %{dir: dir} do
      path = write(dir, "a.json", %{"folderUid" => "f", "dashboard" => %{"uid" => "a"}})

      assert {:wrapped, %{"folderUid" => "f", "dashboard" => %{"uid" => "a"}}} =
               Grafana.read_doc!(path)
    end

    test "reads a bare, hand-authored dashboard and defaults its folder", %{dir: dir} do
      path = write(dir, "b.json", %{"uid" => "b", "title" => "t"})

      assert {:bare, %{"folderUid" => "o-que-mudou", "dashboard" => %{"uid" => "b"}}} =
               Grafana.read_doc!(path)
    end

    test "refuses JSON that is not a dashboard", %{dir: dir} do
      path = write(dir, "c.json", %{"nope" => true})
      assert_raise Mix.Error, ~r/not a dashboard/, fn -> Grafana.read_doc!(path) end
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
