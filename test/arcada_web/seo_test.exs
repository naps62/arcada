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

    test "front door ships WebSite + SearchAction and Organization JSON-LD" do
      %{json_ld: nodes} = SEO.metadata_for(:home)

      website = Enum.find(nodes, &(&1["@type"] == "WebSite"))
      assert website["potentialAction"]["@type"] == "SearchAction"
      assert website["potentialAction"]["target"]["urlTemplate"] =~ "?q={search_term_string}"

      org = Enum.find(nodes, &(&1["@type"] == "Organization"))
      assert org["name"] == "Arcada"
      assert org["logo"] == SEO.url("/icon-512.png")
      assert org["url"] == SEO.url("/")
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

    test "section_heading: nil at root, capitalised scope when filtered" do
      assert SEO.section_heading(nil, nil) == nil
      assert SEO.section_heading("fiscal", nil) == "Fiscal"
      assert SEO.section_heading(nil, :semana) == "Esta semana"
      assert SEO.section_heading("habitação", :mes) == "Habitação · Este mês"
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
    test "headline drives the title; ships Article + Breadcrumb JSON-LD" do
      act = %Act{
        id: 42,
        dre_id: "84",
        tipo: "Decreto",
        title: "Decreto n.º 84/2026",
        source_url: "https://diariodarepublica.pt/x",
        published_at: ~D[2026-06-24],
        updated_at: ~U[2026-06-25 10:00:00Z]
      }

      summary = %Summary{
        headline: "Muda o [[IVA]]",
        plain_text: "Em linguagem simples: muda X.",
        domains: [:fiscal, :trabalho]
      }

      m = SEO.metadata_for({:act, act, summary})

      # [[term]] markers stripped from the headline
      assert m.page_title == "Muda o IVA"
      assert m.page_description == "Em linguagem simples: muda X."
      # canonical keys on the stable dre_id with a decorative title slug
      assert m.canonical_url == SEO.url("/acts/84/decreto-n-84-2026")
      assert m.og_type == "article"

      article = Enum.find(m.json_ld, &(&1["@type"] == "Article"))
      assert article["headline"] == "Muda o IVA"
      assert article["mainEntityOfPage"] == SEO.url("/acts/84/decreto-n-84-2026")
      assert article["datePublished"] == "2026-06-24"
      assert article["dateModified"] == "2026-06-25T10:00:00Z"
      assert article["articleSection"] == "Decreto"
      assert article["isBasedOn"] == "https://diariodarepublica.pt/x"
      assert article["publisher"]["logo"]["url"] == SEO.url("/icon-512.png")

      assert article["author"] == %{
               "@type" => "Organization",
               "name" => "Arcada",
               "url" => SEO.url("/")
             }

      # og:image + Article image point at the per-act generated card
      og = SEO.url("/acts/84/og.png")
      assert m.page_og_image == og
      assert article["image"] == og
      assert m.page_og_image_alt == "Muda o IVA — Arcada"

      # Breadcrumb: Home > first life-domain (linked to its section) > act
      crumbs =
        m.json_ld
        |> Enum.find(&(&1["@type"] == "BreadcrumbList"))
        |> Map.fetch!("itemListElement")

      assert Enum.map(crumbs, &{&1["position"], &1["name"]}) ==
               [{1, "Arcada"}, {2, "fiscal"}, {3, "Muda o IVA"}]

      assert Enum.at(crumbs, 1)["item"] == SEO.url("/?domain=fiscal")
      assert List.last(crumbs)["item"] == SEO.url("/acts/84/decreto-n-84-2026")
    end

    test "falls back to the act title/description when there's no summary" do
      act = %Act{id: 7, dre_id: "7", tipo: "Portaria", title: "Portaria n.º 7/2026"}

      m = SEO.metadata_for({:act, act, nil})

      assert m.page_title == "Portaria n.º 7/2026"
      assert m.page_description == "Portaria n.º 7/2026"

      article = Enum.find(m.json_ld, &(&1["@type"] == "Article"))
      # optional Article fields absent when the act has no date/source
      refute Map.has_key?(article, "datePublished")
      refute Map.has_key?(article, "isBasedOn")

      # No summary/domain → flat Home > act breadcrumb (2 items)
      crumbs =
        m.json_ld
        |> Enum.find(&(&1["@type"] == "BreadcrumbList"))
        |> Map.fetch!("itemListElement")

      assert Enum.map(crumbs, & &1["name"]) == ["Arcada", "Portaria n.º 7/2026"]
    end

    test "long descriptions are truncated with an ellipsis" do
      act = %Act{id: 1, dre_id: "1", title: String.duplicate("a", 500)}
      m = SEO.metadata_for({:act, act, nil})

      assert String.length(m.page_description) == 300
      assert String.ends_with?(m.page_description, "…")
    end
  end
end
