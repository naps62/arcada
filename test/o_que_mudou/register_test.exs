defmodule OQueMudou.RegisterTest do
  use OQueMudou.DataCase, async: true

  alias OQueMudou.Repo
  alias OQueMudou.Register.{Edition, Act, Summary}

  defp insert_edition(attrs \\ %{}) do
    %{serie: "I", number: "118/2026", date: ~D[2026-06-24]}
    |> Map.merge(attrs)
    |> then(&Edition.changeset(%Edition{}, &1))
    |> Repo.insert!()
  end

  defp insert_act(edition, attrs \\ %{}) do
    %{edition_id: edition.id, dre_id: "1138160247"}
    |> Map.merge(attrs)
    |> then(&Act.changeset(%Act{}, &1))
    |> Repo.insert!()
  end

  describe "Edition.changeset/2" do
    test "requires serie, number, date" do
      changeset = Edition.changeset(%Edition{}, %{})

      assert %{serie: ["can't be blank"], number: ["can't be blank"], date: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "valid with required fields" do
      assert Edition.changeset(%Edition{}, %{serie: "I", number: "118/2026", date: ~D[2026-06-24]}).valid?
    end

    test "enforces unique (serie, number)" do
      insert_edition()

      assert {:error, changeset} =
               %Edition{}
               |> Edition.changeset(%{serie: "I", number: "118/2026", date: ~D[2026-06-25]})
               |> Repo.insert()

      assert %{serie: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "Act.changeset/2" do
    setup do
      %{edition: insert_edition()}
    end

    test "requires edition_id and dre_id", %{edition: _edition} do
      changeset = Act.changeset(%Act{}, %{})
      assert %{edition_id: ["can't be blank"], dre_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "persists with full fields", %{edition: edition} do
      act =
        insert_act(edition, %{
          tipo: "Decreto do Presidente da República",
          emitter: "Presidência da República",
          title: "Decreto do Presidente da República n.º 84/2026",
          pdf_url: "https://files.diariodarepublica.pt/1s/2026/06/12000/0000300003.pdf",
          published_at: ~D[2026-06-24]
        })

      assert act.id
      assert act.emitter == "Presidência da República"
    end

    test "enforces unique dre_id", %{edition: edition} do
      insert_act(edition)

      assert {:error, changeset} =
               %Act{}
               |> Act.changeset(%{edition_id: edition.id, dre_id: "1138160247"})
               |> Repo.insert()

      assert %{dre_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "Summary.changeset/2" do
    setup do
      edition = insert_edition()
      %{act: insert_act(edition)}
    end

    test "requires act_id and plain_text", %{act: _act} do
      changeset = Summary.changeset(%Summary{}, %{})
      assert %{act_id: ["can't be blank"], plain_text: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults status to :unreviewed and domains to []", %{act: act} do
      summary =
        %Summary{}
        |> Summary.changeset(%{act_id: act.id, plain_text: "Em linguagem simples..."})
        |> Repo.insert!()

      assert summary.status == :unreviewed
      assert summary.domains == []
      assert is_nil(summary.validated_at)
    end

    test "accepts valid life-domains", %{act: act} do
      summary =
        %Summary{}
        |> Summary.changeset(%{
          act_id: act.id,
          plain_text: "...",
          domains: [:fiscal, :trabalho]
        })
        |> Repo.insert!()

      assert summary.domains == [:fiscal, :trabalho]
    end

    test "rejects unknown life-domain", %{act: act} do
      changeset =
        Summary.changeset(%Summary{}, %{act_id: act.id, plain_text: "...", domains: [:cripto]})

      refute changeset.valid?
      assert %{domains: [_]} = errors_on(changeset)
    end

    test "rejects unknown status", %{act: act} do
      changeset =
        Summary.changeset(%Summary{}, %{act_id: act.id, plain_text: "...", status: :bogus})

      refute changeset.valid?
      assert %{status: [_]} = errors_on(changeset)
    end
  end

  test "Register.life_domains/0 exposes the fixed taxonomy" do
    assert "fiscal" in OQueMudou.Register.life_domains()
    assert "administração" in OQueMudou.Register.life_domains()
    assert length(OQueMudou.Register.life_domains()) == 10
  end
end
