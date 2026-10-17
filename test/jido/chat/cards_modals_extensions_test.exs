defmodule Jido.Chat.CardsModalsExtensionsTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.{Card, Modal}
  alias Jido.Chat.Card.{ChartData, ChartSeries}

  test "constructors accept atom and string maps and keep chart data typed" do
    pie = Card.pie_chart([{"Ready", 3}, %{"label" => "Failed", "value" => 1}])

    bar =
      Card.bar_chart(
        [%{label: "Jan", value: 10}, %{label: "Feb", value: 12, series: "API"}],
        %{"title" => "Requests", "caption" => "Monthly totals"}
      )

    assert pie.kind == :pie_chart
    assert [%ChartData{label: "Ready", value: 3}, %ChartData{label: "Failed", value: 1}] = pie.data
    assert bar.title == "Requests"
    assert bar.caption == "Monthly totals"
    assert Enum.at(bar.data, 1).series == "API"
    assert Card.area_chart([%{label: "Mon", value: 2}]).kind == :area_chart
    assert Card.line_chart([%{label: "Mon", value: 2}]).kind == :line_chart
  end

  test "named series align unambiguously with ordered shared categories" do
    chart =
      Card.line_chart(
        ["Jan", "Feb"],
        [%{name: "API", values: ~c"\n\f"}, %{"name" => "Worker", "values" => ~c"\a\t"}],
        title: "Requests"
      )

    assert chart.categories == ["Jan", "Feb"]

    assert [
             %ChartSeries{name: "API", values: ~c"\n\f"},
             %ChartSeries{name: "Worker", values: ~c"\a\t"}
           ] = chart.series

    assert Card.fallback_text(Card.new(%{components: [chart]})) ==
             "Requests\n\nLine chart. API — Jan: 10, Feb: 12; Worker — Jan: 7, Feb: 9."

    assert_raise Jido.Chat.Errors.Validation, fn ->
      Card.line_chart(["Jan", "Feb"], [%{name: "API", values: ~c"\n"}], [])
    end

    assert_raise Jido.Chat.Errors.Validation, fn ->
      Card.bar_chart(["Jan"], [%{name: "API", values: ~c"\n"}, %{name: "API", values: ~c"\f"}], [])
    end

    assert_raise Jido.Chat.Errors.Validation, fn ->
      Card.Component.new(%{
        kind: :line_chart,
        data: [%{label: "Jan", value: 10}],
        categories: ["Jan"],
        series: [%{name: "API", values: ~c"\n"}]
      })
    end
  end

  test "table accepts caption and any positive page size without provider limits" do
    table =
      Card.table(["Name", "State"], [["api", "ok"]], caption: "Service health", page_size: 50000)

    assert table.caption == "Service health"
    assert table.page_size == 50000

    assert_raise Jido.Chat.Errors.Validation, fn ->
      Card.table(["Name"], [["api"]], page_size: 0)
    end

    assert_raise Jido.Chat.Errors.Validation, fn -> Card.table(["Name", "State"], [["api"]]) end
  end

  test "charts and tables have deterministic readable fallbacks" do
    card =
      Card.new(%{
        components: [
          Card.line_chart([{"Mon", 2}, {"Tue", 4}],
            title: "Traffic",
            caption: "Requests per minute"
          ),
          Card.table(["Service", "State"], [["api", "ok"]], caption: "Current health")
        ]
      })

    assert Card.fallback_text(card) ==
             "Traffic\n\nRequests per minute\n\nLine chart. Mon: 2; Tue: 4.\n\nCurrent health\n\nService | State\n--------+------\napi     | ok"
  end

  test "each chart type and table exposes non-empty adapter fallback text" do
    components = [
      Card.pie_chart([{"Ready", 3}]),
      Card.bar_chart([{"Ready", 3}]),
      Card.area_chart([{"Ready", 3}]),
      Card.line_chart([{"Ready", 3}]),
      Card.table(["State"], [["ready"]], caption: "Health")
    ]

    Enum.each(components, fn component ->
      card = Card.new(%{components: [component]})
      assert Card.fallback_text(card) != ""
      assert Card.to_adapter_payload(card)["fallback_text"] == Card.fallback_text(card)
    end)
  end

  test "chart data boundaries reject empty data and non-numeric values" do
    assert_raise Jido.Chat.Errors.Validation, fn -> Card.pie_chart([]) end

    assert_raise Jido.Chat.Errors.Validation, fn ->
      Card.bar_chart([%{label: "bad", value: "not-a-number"}])
    end
  end

  test "external selects accept initial options and option groups" do
    card_select =
      Card.external_select("assignee",
        label: "Assignee",
        min_query_length: 2,
        timeout_ms: 1500,
        options: [Card.select_option("Ada", "user:ada")],
        option_groups: [
          Card.select_option_group("Teams", [Card.select_option("Core", "team:core")])
        ]
      )

    modal_select =
      Modal.external_select("assignee", "Assignee", min_query_length: 2, timeout_ms: 1500)

    assert card_select.kind == :external_select
    assert card_select.options_source == :external
    assert hd(card_select.option_groups).kind == :option_group
    assert modal_select.kind == :external_select
    assert modal_select.options_source == :external

    assert_raise Jido.Chat.Errors.Validation, fn ->
      Modal.external_select("bad", "Bad", min_query_length: -1)
    end

    assert_raise Jido.Chat.Errors.Validation, fn -> Card.external_select("bad", timeout_ms: 0) end
  end

  test "date and number constructors validate portable boundaries" do
    date =
      Modal.date_input("start_date", "Start date",
        value: ~D[2026-08-20],
        min_date: ~D[2026-01-01],
        max_date: "2026-12-31",
        required: true
      )

    number =
      Modal.number_input("amount", "Amount", value: 12.5, min_value: 0, max_value: 100, step: 0.5)

    assert date.value == "2026-08-20"
    assert date.min_date == "2026-01-01"
    assert number.value == "12.5"
    assert number.step == 0.5

    assert_raise Jido.Chat.Errors.Validation, fn ->
      Modal.date_input("date", "Date", min_date: "2026-12-31", max_date: "2026-01-01")
    end

    assert_raise Jido.Chat.Errors.Validation, fn ->
      Modal.number_input("number", "Number", min_value: 10, max_value: 1)
    end

    assert_raise Jido.Chat.Errors.Validation, fn ->
      Modal.number_input("number", "Number", step: 0)
    end
  end

  test "modal fallback text describes inputs and constraints" do
    modal =
      Modal.new(%{
        title: "Report",
        elements: [
          Modal.date_input("day", "Day", required: true, min_date: "2026-01-01"),
          Modal.number_input("count", "Count", min_value: 1, max_value: 10)
        ]
      })

    assert Modal.fallback_text(modal) ==
             "Report\nDay (date input, required). Minimum date: 2026-01-01.\nCount (number input). Minimum: 1. Maximum: 10."

    assert Modal.to_adapter_payload(modal)["fallback_text"] == Modal.fallback_text(modal)
  end

  test "each input type has deterministic readable fallback text" do
    modal =
      Modal.new(%{
        title: "Inputs",
        elements: [
          Modal.text_input("name", "Name"),
          Modal.date_input("day", "Day"),
          Modal.number_input("count", "Count"),
          Modal.select("state", "State", [Modal.select_option("Ready", "ready")]),
          Modal.radio_select("mode", "Mode", [Modal.select_option("Safe", "safe")]),
          Modal.external_select("owner", "Owner")
        ]
      })

    fallback = Modal.fallback_text(modal)
    assert fallback == Modal.fallback_text(modal)

    for label <- ["Name", "Day", "Count", "State", "Mode", "Owner"] do
      assert fallback =~ label
    end
  end

  test "string-key card and modal maps normalize all new element kinds" do
    card =
      Card.new(%{
        "components" => [
          %{"kind" => "bar_chart", "data" => [%{"label" => "Ready", "value" => 3}]},
          %{
            "kind" => "table",
            "caption" => "Health",
            "columns" => ["State"],
            "rows" => [["ready"]],
            "page_size" => 100
          }
        ]
      })

    modal =
      Modal.new(%{
        "title" => "Report",
        "elements" => [
          %{"kind" => "date_input", "id" => "day", "label" => "Day"},
          %{"kind" => "number_input", "id" => "count", "label" => "Count"},
          %{
            "kind" => "external_select",
            "id" => "owner",
            "label" => "Owner",
            "options_source" => "dynamic"
          }
        ]
      })

    assert Enum.map(card.components, & &1.kind) == [:bar_chart, :table]
    assert Enum.map(modal.elements, & &1.kind) == [:date_input, :number_input, :external_select]
    assert List.last(modal.elements).options_source == :dynamic
  end
end
