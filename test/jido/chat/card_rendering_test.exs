defmodule Jido.Chat.CardRenderingTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Card, Markdown}
  alias Jido.Chat.Card.{ChartData, ChartSeries, Component}

  test "grouped content and actions retain their text in Markdown and adapter payloads" do
    card =
      Card.new(%{title: "Report", summary: "Summary", markdown: "Intro"})
      |> Card.add(Card.section(title: "Details", text: "Body", markdown: "Note", items: [Card.field("Owner", "Ada")]))
      |> Card.add(Card.fields([Card.field("State", "Ready")], title: "Facts"))
      |> Card.add(
        Card.actions([Card.button("Run", "run"), Card.link_button("Docs", "https://example.test")], title: "Actions")
      )
      |> Card.add(Card.link("Home", "https://example.test/home"))
      |> Card.add(Card.image("https://example.test/image.png", alt_text: "Chart"))
      |> Card.add(Card.divider())

    markdown = Card.to_markdown(card) |> Markdown.stringify()

    assert markdown ==
             "## Report\n\nSummary\n\nIntro\n\n### Details\n\nBody\n\nNote\n\nOwner: Ada\n\n### Facts\n\nState: Ready\n\n### Actions\n\n- Run\n\n- [Docs](https://example.test)\n\n[Home](https://example.test/home)\n\nChart\n\n---"

    payload = Card.to_adapter_payload(card)
    assert payload["fallback_text"] == Card.fallback_text(card)
    assert payload["markdown"] == "Intro"
    assert Enum.at(payload["components"], 0)["markdown"] == "Note"
    assert Card.normalize(card) == card
    assert Card.new(card) == card
    assert Card.fallback_text(Card.normalize(%{components: ["Text"]})) == "Text"
  end

  test "selection controls expose ordered options, groups and external fallback text" do
    options = [Card.select_option("One", "1"), Component.new(%{kind: :select_option, text: "Two"})]
    group = Card.select_option_group("Group", options)

    components = [
      Card.select("pick", options, label: "Pick"),
      Card.radio_select("radio", options, title: "Radio"),
      group,
      Card.external_select("external", options: options, option_groups: [group]),
      Card.dynamic_select("dynamic", fallback_text: "Search"),
      Card.external_select("empty")
    ]

    card = Card.new(%{components: components})

    assert Card.to_markdown(card) |> Markdown.stringify() ==
             "#### Pick\n\n- One\n- Two\n\n#### Radio\n\n- One\n- Two\n\n#### Group\n\n- One\n- Two\n\n#### external\n\nInitial options: One, Two, One, Two.\n\n#### dynamic\n\nSearch\n\n#### empty\n\nOptions load as you type."

    assert Enum.at(components, 4).options_source == :dynamic

    assert Card.to_adapter_payload(card)["components"]
           |> Enum.at(3)
           |> Map.fetch!("option_groups")
           |> hd()
           |> Map.fetch!("label") == "Group"
  end

  test "component default labels provide readable fallbacks" do
    components = [
      Component.new(%{kind: :text}),
      Component.new(%{kind: :field, value: "Value"}),
      Component.new(%{kind: :button}),
      Component.new(%{kind: :link_button}),
      Component.new(%{kind: :link}),
      Component.new(%{kind: :select, options: [%{kind: :select_option}]}),
      Component.new(%{kind: :radio_select}),
      Component.new(%{kind: :image})
    ]

    markdown = Card.new(%{components: components}) |> Card.to_markdown() |> Markdown.stringify()
    assert markdown =~ "Field: Value"
    assert markdown =~ "- Action"
    assert markdown =~ "- [Open](#)"
    assert markdown =~ "[Link](#)"
    assert markdown =~ "#### Select\n\n- option"
    assert markdown =~ "#### Options"
    assert String.ends_with?(markdown, "image")
  end

  test "chart types retain their values, named series and explicit fallback priority" do
    for {builder, label} <- [
          {:pie_chart, "Pie chart"},
          {:bar_chart, "Bar chart"},
          {:area_chart, "Area chart"},
          {:line_chart, "Line chart"}
        ] do
      component = apply(Card, builder, [[%{label: "A", value: 1.5, series: "S"}]])
      assert Card.fallback_text(Card.new(%{components: [component]})) == "#{label}. S — A: 1.5."
    end

    for type <- [:pie, :bar, :area, :line, "pie", "bar", "area", "line"] do
      component = Card.chart(type, [{"A", 2}], %{title: "Chart", caption: "Data"})
      assert Card.fallback_text(Card.new(%{components: [component]})) =~ "A: 2"
    end

    for builder <- [:bar_chart, :area_chart, :line_chart] do
      component = apply(Card, builder, [["A", "B"], [{"Total", [2, 3]}], []])
      assert Card.fallback_text(Card.new(%{components: [component]})) =~ "Total — A: 2, B: 3"
    end

    component = Card.line_chart([{"A", 1}], alt_text: "Accessible", fallback_text: "Chosen")
    assert Card.fallback_text(Card.new(%{components: [component]})) == "Chosen"

    assert Card.fallback_text(Card.new(%{components: [Card.area_chart([{"A", 1}], alt_text: "Accessible")]})) ==
             "Accessible"
  end

  test "tables retain titles and captions, and link IDs are stable or caller supplied" do
    table = Card.table(["Name", "N"], [["Ada", "2"]], title: "Table", caption: "Count", page_size: 10)

    assert Card.to_markdown(Card.new(%{components: [table]})) |> Markdown.stringify() ==
             "### Table\n\nCount\n\n| Name | N |\n| --- | --- |\n| Ada | 2 |"

    assert table.page_size == 10
    assert Card.link_button("Docs", "https://example.test").id == Card.link_button("Docs", "https://example.test").id
    refute Card.link_button("Docs", "https://example.test").id == Card.link_button("Other", "https://example.test").id
    assert Card.link_button("Docs", "https://example.test", "explicit").id == "explicit"
    assert Card.link_button("Docs", "https://example.test", "explicit", disabled: true).disabled
  end

  test "typed components and chart values retain their wire representation" do
    markdown = Markdown.root([Markdown.strong("Bold")])
    component = Card.text("Fallback", %{markdown: markdown})
    card = Card.new(%{components: [component, Card.select_option("One", "1", text: "Detail")]})
    assert Card.to_adapter_payload(card)["components"] |> hd() |> Map.fetch!("markdown") == "**Bold**"
    assert Card.to_map(Card.from_map(Card.to_map(card))) == Card.to_map(card)
    assert Component.to_map(Component.from_map(Component.to_map(component))) == Component.to_map(component)
    point = ChartData.new({"A", 2})
    series = ChartSeries.new({"S", [1, 2.5]})
    assert ChartData.new(point) == point
    assert ChartSeries.new(series) == series
    assert ChartData.from_map(ChartData.to_map(point)) == point
    assert ChartSeries.from_map(ChartSeries.to_map(series)) == series
    assert Zoi.parse(ChartData.schema(), %{label: "A", value: "invalid"}) |> elem(0) == :error
    assert Zoi.parse(ChartSeries.schema(), %{name: "S", values: ["invalid"]}) |> elem(0) == :error
    assert Zoi.parse(Card.schema(), %{components: :invalid}) |> elem(0) == :error
  end
end
