defmodule OQueMudou.Register.EmbeddingTest do
  use ExUnit.Case, async: true

  alias OQueMudou.Register.Embedding

  test "type is :binary" do
    assert Embedding.type() == :binary
  end

  test "cast accepts a list of numbers" do
    assert Embedding.cast([1.0, -2.5, 0.0]) == {:ok, [1.0, -2.5, 0.0]}
    assert Embedding.cast("nope") == :error
  end

  test "dump/load round-trips floats through the float32 packing" do
    vector = [1.0, -2.5, 0.0, 3.375]
    assert {:ok, packed} = Embedding.dump(vector)
    assert is_binary(packed)
    assert byte_size(packed) == length(vector) * 4
    assert {:ok, loaded} = Embedding.load(packed)
    assert loaded == vector
  end

  test "dump rejects non-lists" do
    assert Embedding.dump("nope") == :error
  end

  test "load of an empty binary is an empty vector" do
    assert Embedding.load(<<>>) == {:ok, []}
  end
end
