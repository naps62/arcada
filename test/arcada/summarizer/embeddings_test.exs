defmodule Arcada.Summarizer.EmbeddingsTest do
  use ExUnit.Case, async: true

  alias Arcada.Summarizer.Embeddings

  test "cosine similarity" do
    assert Embeddings.cosine([1.0, 0.0], [1.0, 0.0]) == 1.0
    assert Embeddings.cosine([1.0, 0.0], [0.0, 1.0]) == 0.0
    assert_in_delta Embeddings.cosine([1.0, 1.0], [1.0, 0.0]), 0.7071, 0.0001
    # zero vector never blows up
    assert Embeddings.cosine([0.0, 0.0], [1.0, 2.0]) == 0.0
  end

  test "enabled? requires a base_url or an injected fn" do
    refute Embeddings.enabled?([])
    refute Embeddings.enabled?(base_url: "")
    assert Embeddings.enabled?(base_url: "http://localhost:8080")
    assert Embeddings.enabled?(embed_fn: fn _ -> {:ok, []} end)
  end

  test "embed delegates to the injected fn, preserving order" do
    cfg = [embed_fn: fn texts -> {:ok, Enum.map(texts, &[String.length(&1) * 1.0])} end]
    assert {:ok, [[1.0], [2.0], [3.0]]} = Embeddings.embed(["a", "bb", "ccc"], cfg)
  end

  test "endpoint_url tolerates a base with or without /v1" do
    assert Embeddings.endpoint_url("https://h") == "https://h/v1/embeddings"
    assert Embeddings.endpoint_url("https://h/") == "https://h/v1/embeddings"
    assert Embeddings.endpoint_url("https://h/v1") == "https://h/v1/embeddings"
    assert Embeddings.endpoint_url("https://h/v1/") == "https://h/v1/embeddings"
  end
end
