defmodule Arcada.OgImageTest do
  use ExUnit.Case, async: true

  alias Arcada.OgImage
  alias Arcada.Register.{Act, Summary}

  defp act(attrs \\ %{}),
    do:
      struct(
        %Act{tipo: "Decreto-Lei", published_at: ~D[2026-07-11], title: "Decreto n.º 1"},
        attrs
      )

  describe "svg/2" do
    test "uses the plain-language headline over the formal title" do
      # (headline words may be split across wrapped <tspan> lines)
      svg = OgImage.svg(act(), %Summary{headline: "Sobe o salário mínimo"})
      assert svg =~ "salário"
      assert svg =~ "mínimo"
      refute svg =~ "Decreto n.º 1"
    end

    test "falls back to the act title when there is no summary" do
      assert OgImage.svg(act(), nil) =~ "Decreto n.º 1"
    end

    test "renders an upcased tipo chip and a Portuguese date" do
      svg = OgImage.svg(act(), nil)
      assert svg =~ "DECRETO-LEI"
      assert svg =~ "11 julho 2026"
    end

    test "escapes XML-significant characters in the headline" do
      svg = OgImage.svg(act(), %Summary{headline: ~s(Taxa <alta> & "nova")})
      assert svg =~ "&lt;alta&gt;"
      assert svg =~ "&amp;"
      assert svg =~ "&quot;"
      refute svg =~ "<alta>"
    end

    test "wraps and caps a very long headline with an ellipsis" do
      long = String.duplicate("palavra ", 60)
      svg = OgImage.svg(act(), %Summary{headline: long})
      assert svg =~ "…"
      # never more than 4 headline lines
      assert svg |> String.split("<tspan") |> length() |> Kernel.-(1) <= 4
    end

    test "omits chip/date cleanly when absent" do
      svg = OgImage.svg(%Act{title: "Sem tipo"}, nil)
      refute svg =~ "font-size=\"26\""
      assert svg =~ "arcada.naps.pt"
    end
  end

  # Real rasterisation needs rsvg-convert + the render fonts; present in the
  # runtime container and in CI, but not on every dev box.
  if System.find_executable("rsvg-convert") do
    describe "png/1" do
      test "produces a PNG" do
        assert {:ok, png} = OgImage.png(act())
        assert <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>> = png
        assert byte_size(png) > 1000
      end
    end
  end
end
