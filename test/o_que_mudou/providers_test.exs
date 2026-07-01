defmodule OQueMudou.ProvidersTest do
  use OQueMudou.DataCase, async: true

  alias OQueMudou.Providers

  test "creates an anthropic provider and splits the models string" do
    assert {:ok, p} =
             Providers.create_provider(%{
               "name" => "claude",
               "kind" => "anthropic",
               "api_key" => "sk-x",
               "models" => "claude-opus-4-8, claude-sonnet-4-6\nclaude-haiku-4-5"
             })

    assert p.kind == :anthropic
    assert p.models == ["claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5"]
  end

  test "openai requires base_url; ssh requires host" do
    assert {:error, cs} = Providers.create_provider(%{"name" => "o", "kind" => "openai"})
    assert "can't be blank" in errors_on(cs).base_url

    assert {:error, cs} = Providers.create_provider(%{"name" => "s", "kind" => "ssh"})
    assert "can't be blank" in errors_on(cs).ssh_host
  end

  test "names are unique" do
    {:ok, _} = Providers.create_provider(%{"name" => "dup", "kind" => "anthropic"})
    assert {:error, cs} = Providers.create_provider(%{"name" => "dup", "kind" => "anthropic"})
    assert "has already been taken" in errors_on(cs).name
  end

  test "max_concurrency defaults by kind and honours an explicit value" do
    {:ok, ssh} = Providers.create_provider(%{"name" => "s", "kind" => "ssh", "ssh_host" => "h"})
    assert ssh.max_concurrency == 1

    {:ok, api} = Providers.create_provider(%{"name" => "a", "kind" => "anthropic"})
    assert api.max_concurrency == 5

    {:ok, custom} =
      Providers.create_provider(%{"name" => "c", "kind" => "anthropic", "max_concurrency" => "12"})

    assert custom.max_concurrency == 12
  end

  test "max_concurrency must be positive" do
    assert {:error, cs} =
             Providers.create_provider(%{
               "name" => "z",
               "kind" => "anthropic",
               "max_concurrency" => "0"
             })

    assert "must be greater than 0" in errors_on(cs).max_concurrency
  end

  test "lists, enabled-filters, and deletes" do
    {:ok, on} = Providers.create_provider(%{"name" => "on", "kind" => "anthropic"})

    {:ok, off} =
      Providers.create_provider(%{"name" => "off", "kind" => "anthropic", "enabled" => "false"})

    assert length(Providers.list_providers()) == 2
    assert Enum.map(Providers.enabled_providers(), & &1.id) == [on.id]

    {:ok, _} = Providers.delete_provider(off)
    assert length(Providers.list_providers()) == 1
  end
end
