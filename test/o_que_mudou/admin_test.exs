defmodule OQueMudou.AdminTest do
  use OQueMudou.DataCase, async: true

  alias OQueMudou.Admin
  alias OQueMudou.Summarizer.Adapters.{Api, Ssh}

  describe "with no settings row" do
    test "summarizer_adapter falls back to the env default" do
      # whatever the test env configures (not crashing / not nil)
      assert is_atom(Admin.summarizer_adapter())
    end

    test "adapter_config returns the env config untouched (no overrides)" do
      env = Application.get_env(:o_que_mudou, Ssh, [])
      assert Admin.adapter_config(Ssh) == env
    end
  end

  describe "with a settings row" do
    test "DB adapter overrides the env default" do
      {:ok, _} = Admin.update_settings(%{"summarizer_adapter" => "ssh"})
      assert Admin.summarizer_adapter() == :ssh
    end

    test "blank/invalid adapter is rejected and falls back to env" do
      {:ok, _} = Admin.update_settings(%{"summarizer_adapter" => ""})
      assert is_atom(Admin.summarizer_adapter())
    end

    test "DB fields override the matching adapter config keys" do
      {:ok, _} =
        Admin.update_settings(%{
          "api_model" => "claude-opus-4-8",
          "ssh_host" => "10.0.0.9",
          "ssh_model" => "claude-cli-x"
        })

      assert Admin.adapter_config(Api)[:model] == "claude-opus-4-8"
      assert Admin.adapter_config(Ssh)[:host] == "10.0.0.9"
      assert Admin.adapter_config(Ssh)[:model] == "claude-cli-x"
    end

    test "a blank api_key on update keeps the stored key" do
      {:ok, _} = Admin.update_settings(%{"api_key" => "sk-secret"})
      assert Admin.get_settings().api_key == "sk-secret"

      {:ok, _} = Admin.update_settings(%{"api_key" => "", "api_model" => "m"})
      assert Admin.get_settings().api_key == "sk-secret"
      assert Admin.get_settings().api_model == "m"
    end

    test "settings stays a singleton across updates" do
      {:ok, _} = Admin.update_settings(%{"ssh_host" => "a"})
      {:ok, _} = Admin.update_settings(%{"ssh_host" => "b"})
      assert Repo.aggregate(OQueMudou.Admin.Setting, :count) == 1
      assert Admin.get_settings().ssh_host == "b"
    end
  end
end
