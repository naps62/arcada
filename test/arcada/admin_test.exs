defmodule Arcada.AdminTest do
  use Arcada.DataCase, async: true

  import Arcada.SummarizerHelpers

  alias Arcada.Admin

  test "no active provider by default" do
    assert is_nil(Admin.active_provider())
    assert is_nil(Admin.active_model())
  end

  test "sets and reads the active provider + model" do
    provider = ssh_provider()

    {:ok, _} =
      Admin.update_settings(%{
        "active_provider_id" => provider.id,
        "active_model" => "claude-cli"
      })

    assert Admin.active_provider().id == provider.id
    assert Admin.active_model() == "claude-cli"
  end

  test "settings stays a singleton" do
    p1 = ssh_provider()
    p2 = ssh_provider()
    {:ok, _} = Admin.update_settings(%{"active_provider_id" => p1.id})
    {:ok, _} = Admin.update_settings(%{"active_provider_id" => p2.id})

    assert Repo.aggregate(Arcada.Admin.Setting, :count) == 1
    assert Admin.active_provider().id == p2.id
  end

  test "a blank active_provider_id clears it" do
    provider = ssh_provider()
    {:ok, _} = Admin.update_settings(%{"active_provider_id" => provider.id})
    {:ok, _} = Admin.update_settings(%{"active_provider_id" => ""})
    assert is_nil(Admin.active_provider())
  end
end
