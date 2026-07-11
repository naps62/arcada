defmodule ArcadaWeb.SEOTest do
  use ExUnit.Case, async: true

  alias ArcadaWeb.SEO
  alias Arcada.Register.{Act, Summary}

  describe "metadata_for :home / {:browse, nil, nil}" do
    test ":home and the unfiltered browse are the same front-door metadata" do
      assert SEO.metadata_for(:home) == SEO.metadata_for({:browse, nil, nil})
    end

    test "no scope prefix, default description, root canonical" do
      m = SEO.metadata_for(:home)

      assert m.page_title == nil
      assert m.page_description == SEO.default_description()
      assert m.canonical_url == SEO.url("/")
      assert m.page_noindex == false
    end

    test "front door ships WebSite + SearchAction JSON-LD" do
      %{json_ld: ld} = SEO.metadata_for(:home)

      assert ld["@type"] == "WebSite"
      assert ld["potentialAction"]["@type"] == "SearchAction"
      assert ld["potentialAction"]["target"]["urlTemplate"] =~ "?q={search_term_string}"
    end
  end

  describe "metadata_for {:browse, domain, period}" do
    test "a filtered view is its own canonical, scoped title, no SearchAction" do
      m = SEO.metadata_for({:browse, "fiscal", :mes})

      assert m.page_title == "fiscal · Este mês"
      assert m.page_description =~ "fiscal · Este mês"
      assert m.canonical_url == SEO.url("/?domain=fiscal&period=mes")
      assert m.json_ld == nil
      assert m.page_noindex == false
    end

    test "domain-only and period-only titles" do
      assert SEO.metadata_for({:browse, "saúde", nil}).page_title == "saúde"
      assert SEO.metadata_for({:browse, nil, :semana}).page_title == "Esta semana"
    end

    test "period-only canonical carries just the period" do
      assert SEO.metadata_for({:browse, nil, :ano}).canonical_url == SEO.url("/?period=ano")
    end
  end

  describe "metadata_for {:search, query}" do
    test "search pages are noindex and canonicalise to the root" do
      m = SEO.metadata_for({:search, "IVA"})

      assert m.page_title == "Pesquisa: IVA"
      assert m.page_noindex == true
      assert m.canonical_url == SEO.url("/")
      assert m.json_ld == nil
    end
  end

  describe "metadata_for {:act, act, summary}" do
    test "headline drives the title; ships an Article JSON-LD with source + date" do
      act = %Act{
        id: 42,
        dre_id: "84",
        tipo: "Decreto",
        title: "Decreto n.º 84/2026",
        source_url: "https://diariodarepublica.pt/x",
        published_at: ~D[2026-06-24]
      }

      summary = %Summary{headline: "Muda o [[IVA]]", plain_text: "Em linguagem simples: muda X."}

      m = SEO.metadata_for({:act, act, summary})

      # [[term]] markers stripped from the headline
      assert m.page_title == "Muda o IVA"
      assert m.page_description == "Em linguagem simples: muda X."
      # canonical keys on the stable dre_id with a decorative title slug
      assert m.canonical_url == SEO.url("/acts/84/decreto-n-84-2026")
      assert m.og_type == "article"

      ld = m.json_ld
      assert ld["@type"] == "Article"
      assert ld["headline"] == "Muda o IVA"
      assert ld["mainEntityOfPage"] == SEO.url("/acts/84/decreto-n-84-2026")
      assert ld["datePublished"] == "2026-06-24"
      assert ld["articleSection"] == "Decreto"
      assert ld["isBasedOn"] == "https://diariodarepublica.pt/x"

      # og:image + Article image point at the per-act generated card
      og = SEO.url("/acts/84/og.png")
      assert m.page_og_image == og
      assert ld["image"] == og
    end

    test "falls back to the act title/description when there's no summary" do
      act = %Act{id: 7, dre_id: "7", tipo: "Portaria", title: "Portaria n.º 7/2026"}

      m = SEO.metadata_for({:act, act, nil})

      assert m.page_title == "Portaria n.º 7/2026"
      assert m.page_description == "Portaria n.º 7/2026"
      # optional Article fields absent when the act has no date/source
      refute Map.has_key?(m.json_ld, "datePublished")
      refute Map.has_key?(m.json_ld, "isBasedOn")
    end

    test "long descriptions are truncated with an ellipsis" do
      act = %Act{id: 1, dre_id: "1", title: String.duplicate("a", 500)}
      m = SEO.metadata_for({:act, act, nil})

      assert String.length(m.page_description) == 300
      assert String.ends_with?(m.page_description, "…")
    end
  end
end
