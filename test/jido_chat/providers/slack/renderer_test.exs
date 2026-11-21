defmodule Jido.Chat.Slack.RendererTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Card, Modal}
  alias Jido.Chat.Slack.Renderer

  test "cards retain readable text and Slack block limits" do
    card =
      Card.new(%{
        title: "Service health",
        components: [
          Card.line_chart(["Mon", "Tue"], [%{name: "API", values: [10, 12]}], title: "Requests"),
          Card.table(["Service", "State"], [["api", "ok"]], caption: "Current health")
        ]
      })

    assert {:ok, rendered} = Renderer.card(card)
    assert rendered.fallback_used
    assert rendered.text =~ "Service health"
    assert Enum.any?(rendered.blocks, &(&1["type"] == "data_table"))
  end

  test "canonical and provider modal maps render as Slack views" do
    modal = Modal.new(%{title: "Survey", callback_id: "survey", private_metadata: ~s({"room_id":"C1"})})
    assert {:ok, %{"type" => "modal", "callback_id" => "survey"}} = Renderer.modal(modal)

    provider = %{"type" => "modal", "title" => %{"type" => "plain_text", "text" => "Native"}, "blocks" => []}
    assert {:ok, ^provider} = Renderer.modal(provider)
  end

  test "canonical option maps render and enforce mutual exclusion" do
    assert {:ok, %{"options" => [%{"text" => %{"text" => "One"}, "value" => "1"}]}} =
             Renderer.options_response(%{"options" => [%{"label" => "One", "value" => "1"}]})

    assert {:error, {:provider_validation, :options_and_groups_are_mutually_exclusive}} =
             Renderer.options_response(%{
               "options" => [%{"label" => "One", "value" => "1"}],
               "option_groups" => [%{"label" => "Group", "options" => []}]
             })
  end

  test "renders canonical card content, controls, and fallbacks in order" do
    option = Card.select_option("Open", "open")
    url = "https://example.com/help"

    card =
      Card.new(%{
        title: "Status",
        summary: "Current incidents",
        components: [
          Card.section(%{
            title: "Service",
            items: [Card.text("API"), Card.field("Owner", "Platform"), Card.fields([Card.field("State", "Open")])]
          }),
          Card.link("Help", url),
          Card.image(url, title: "Status image", alt_text: "Status legend"),
          Card.divider(),
          Card.button("Resolve", "resolve", style: :danger),
          Card.link_button("Help", url, "help"),
          Card.actions(
            [
              Card.select("state", [option], value: "open"),
              Card.radio_select("radio", [option], value: "open"),
              Card.external_select("search", min_query_length: 2)
            ],
            title: "Controls"
          ),
          Card.table(["Count"], [[42]], page_size: 5),
          Card.pie_chart([{"Open", 1}]),
          Card.bar_chart([{"Open", 1}]),
          Card.area_chart([{"Open", 1}])
        ]
      })

    assert {:ok, %{fallback_used: true, blocks: blocks, text: fallback}} = Renderer.card(card)
    assert fallback =~ "42"

    assert [
             %{"type" => "header"},
             %{"text" => %{"text" => "Current incidents"}},
             %{"text" => %{"text" => "*Service*"}},
             %{"text" => %{"text" => "API"}},
             %{"text" => %{"text" => "*Owner*\nPlatform"}},
             %{"fields" => [%{"text" => "*State*\nOpen"}]},
             %{"text" => %{"text" => "<https://example.com/help|Help>"}},
             %{"image_url" => ^url, "alt_text" => "Status legend"},
             %{"type" => "divider"},
             %{"elements" => [%{"action_id" => "resolve", "style" => "danger"}]},
             %{"elements" => [%{"action_id" => "help", "url" => ^url}]},
             %{"text" => %{"text" => "*Controls*"}},
             %{
               "elements" => [
                 %{"type" => "static_select", "initial_option" => %{"value" => "open"}},
                 %{"type" => "radio_buttons", "initial_option" => %{"value" => "open"}},
                 %{"type" => "external_select", "min_query_length" => 2}
               ]
             },
             %{"page_size" => 5, "rows" => [_, [%{"type" => "raw_number", "value" => 42}]]},
             %{"type" => "section"},
             %{"type" => "section"},
             %{"type" => "section"}
           ] = blocks
  end

  test "renders native Slack modal inputs with their initial values" do
    option = Modal.select_option("Open", "open")

    modal =
      Modal.new(%{
        title: "Resolve incident",
        elements: [
          Modal.text_input("title", "Title", value: "API", required: true, help_text: "Service name"),
          Modal.date_input("date", "Date", value: "2026-01-01"),
          Modal.number_input("count", "Count", value: 5, min_value: 1, max_value: 10),
          Modal.select("state", "State", [option], value: "open"),
          Modal.radio_select("radio", "Radio", [option], value: "open"),
          Modal.external_select("search", "Search", value: "open", options: [option], min_query_length: 2)
        ]
      })

    assert {:ok, %{"blocks" => blocks}} = Renderer.modal(modal)

    assert [
             %{
               "optional" => false,
               "hint" => %{"text" => "Service name"},
               "element" => %{"type" => "plain_text_input", "initial_value" => "API"}
             },
             %{"element" => %{"type" => "datepicker", "initial_date" => "2026-01-01"}},
             %{"element" => %{"type" => "number_input", "max_value" => "10", "min_value" => "1"}},
             %{"element" => %{"type" => "static_select", "initial_option" => %{"value" => "open"}}},
             %{"element" => %{"type" => "radio_buttons", "initial_option" => %{"value" => "open"}}},
             %{
               "element" => %{
                 "type" => "external_select",
                 "min_query_length" => 2,
                 "initial_option" => %{"value" => "open"}
               }
             }
           ] = blocks
  end

  test "enforces provider limits and preserves dynamic option groups" do
    options = [%{label: "Open", value: "open", description: "Needs triage"}]

    assert {:ok,
            %{
              "option_groups" => [
                %{
                  "label" => %{"text" => "State"},
                  "options" => [
                    %{"value" => "open", "description" => %{"text" => "Needs triage"}}
                  ]
                }
              ]
            }} = Renderer.options_response(%{option_groups: [%{label: "State", options: options}]})

    assert {:error, {:provider_limit, :group_options, 100}} =
             Renderer.options_response(%{option_groups: [%{label: "State", options: List.duplicate(hd(options), 101)}]})

    assert {:error, {:provider_limit, :message_blocks, 50}} =
             Renderer.card(%{components: List.duplicate(Card.divider(), 51)})

    assert {:error, {:provider_limit, :section_text, 3_000}} =
             Renderer.card(%{components: [Card.text(String.duplicate("x", 3_001))]})

    assert {:error, {:provider_limit, :table_columns, 20}} =
             Renderer.card(%{components: [Card.table(List.duplicate("Name", 21), [List.duplicate("API", 21)])]})

    assert {:error, {:provider_limit, :table_rows, 200}} =
             Renderer.card(%{components: [Card.table(["Name"], List.duplicate(["API"], 201))]})

    assert {:error, {:provider_limit, :table_page_size, 100}} =
             Renderer.card(%{components: [Card.table(["Name"], [["API"]], page_size: 101)]})

    assert {:error, {:provider_limit, :table_characters, 20_000}} =
             Renderer.card(%{components: [Card.table(["Name"], [[String.duplicate("x", 20_001)]])]})

    for {element, kind, field} <- [
          {Modal.date_input("date", "Date", min_date: "2026-01-01"), :date_input, :min_date},
          {Modal.date_input("date", "Date", max_date: "2026-01-01"), :date_input, :max_date},
          {Modal.number_input("count", "Count", step: 2), :number_input, :step}
        ] do
      assert {:error, {:unsupported_constraint, ^kind, ^field}} =
               Renderer.modal(%{title: "Incident", elements: [element]})
    end
  end
end
