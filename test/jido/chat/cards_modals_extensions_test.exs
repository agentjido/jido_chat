defmodule Jido.Chat.CardsModalsExtensionsTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{
    Adapter,
    Card,
    CapabilityMatrix,
    EventEnvelope,
    Modal,
    ModalSubmitEvent,
    OptionsLoadError,
    OptionsLoadEvent,
    OptionsLoadOption,
    OptionsLoadOptionGroup,
    OptionsLoadResult
  }

  alias Jido.Chat.Card.{ChartData, ChartSeries}

  defmodule OptionsAdapter do
    @behaviour Jido.Chat.Adapter

    @impl true
    def channel_type, do: :options_test

    @impl true
    def capabilities do
      %{
        cards: :fallback,
        card_charts: :fallback,
        card_tables: :fallback,
        modal_date_input: :native,
        modal_number_input: :native,
        external_select: :native,
        options_load: :native
      }
    end

    @impl true
    def send_message(_external_room_id, _text, _opts), do: {:error, :not_used}

    @impl true
    def transform_incoming(_payload), do: {:error, :not_used}

    @impl true
    def load_options(%OptionsLoadEvent{query: "timeout"}, _opts), do: {:error, :timeout}

    def load_options(%OptionsLoadEvent{query: "slow", raw: %{test_pid: test_pid}}, _opts) do
      send(test_pid, {:options_load_started, self()})
      Process.sleep(1_000)
      send(test_pid, :options_load_completed)
      {:ok, %{options: []}}
    end

    def load_options(%OptionsLoadEvent{action_id: "assignee"}, _opts) do
      {:ok,
       %{
         options: [%{label: "Ada", value: "user:ada"}],
         option_groups: [
           %{label: "Teams", options: [%{label: "Core", value: "team:core"}]}
         ]
       }}
    end
  end

  describe "chart and table components" do
    test "constructors accept atom and string maps and keep chart data typed" do
      pie = Card.pie_chart([{"Ready", 3}, %{"label" => "Failed", "value" => 1}])

      bar =
        Card.bar_chart(
          [%{label: "Jan", value: 10}, %{label: "Feb", value: 12, series: "API"}],
          %{"title" => "Requests", "caption" => "Monthly totals"}
        )

      assert pie.kind == :pie_chart

      assert [%ChartData{label: "Ready", value: 3}, %ChartData{label: "Failed", value: 1}] =
               pie.data

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
          [
            %{name: "API", values: [10, 12]},
            %{"name" => "Worker", "values" => [7, 9]}
          ],
          title: "Requests"
        )

      assert chart.categories == ["Jan", "Feb"]

      assert [
               %ChartSeries{name: "API", values: [10, 12]},
               %ChartSeries{name: "Worker", values: [7, 9]}
             ] = chart.series

      assert Card.fallback_text(Card.new(%{components: [chart]})) ==
               "Requests\n\nLine chart. API — Jan: 10, Feb: 12; Worker — Jan: 7, Feb: 9."

      assert_raise Jido.Chat.Errors.Validation, fn ->
        Card.line_chart(["Jan", "Feb"], [%{name: "API", values: [10]}], [])
      end

      assert_raise Jido.Chat.Errors.Validation, fn ->
        Card.bar_chart(
          ["Jan"],
          [%{name: "API", values: [10]}, %{name: "API", values: [12]}],
          []
        )
      end

      assert_raise Jido.Chat.Errors.Validation, fn ->
        Card.Component.new(%{
          kind: :line_chart,
          data: [%{label: "Jan", value: 10}],
          categories: ["Jan"],
          series: [%{name: "API", values: [10]}]
        })
      end
    end

    test "table accepts caption and any positive page size without provider limits" do
      table =
        Card.table(["Name", "State"], [["api", "ok"]],
          caption: "Service health",
          page_size: 50_000
        )

      assert table.caption == "Service health"
      assert table.page_size == 50_000

      assert_raise Jido.Chat.Errors.Validation, fn ->
        Card.table(["Name"], [["api"]], page_size: 0)
      end

      assert_raise Jido.Chat.Errors.Validation, fn ->
        Card.table(["Name", "State"], [["api"]])
      end
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
  end

  describe "actions and selects" do
    test "link buttons keep explicit IDs and generate deterministic IDs when absent" do
      explicit =
        Card.link_button("Logs", "https://example.com/logs", action_id: "deploy:logs")

      generated_one = Card.link_button("Logs", "https://example.com/logs")
      generated_two = Card.link_button("Logs", "https://example.com/logs")

      assert explicit.id == "deploy:logs"
      assert generated_one.id == generated_two.id
      assert String.starts_with?(generated_one.id, "link:")

      assert %Card.Component{id: "deploy:logs"} =
               explicit |> Card.Component.to_map() |> Card.Component.from_map()

      assert "deploy:logs" ==
               explicit
               |> Card.Component.to_map()
               |> Jido.Chat.Serialization.revive()
               |> Map.fetch!(:id)
    end

    test "external selects accept initial options and option groups" do
      card_select =
        Card.external_select("assignee",
          label: "Assignee",
          min_query_length: 2,
          timeout_ms: 1_500,
          options: [Card.select_option("Ada", "user:ada")],
          option_groups: [
            Card.select_option_group("Teams", [Card.select_option("Core", "team:core")])
          ]
        )

      modal_select =
        Modal.external_select("assignee", "Assignee",
          min_query_length: 2,
          timeout_ms: 1_500
        )

      assert card_select.kind == :external_select
      assert card_select.options_source == :external
      assert hd(card_select.option_groups).kind == :option_group
      assert modal_select.kind == :external_select
      assert modal_select.options_source == :external

      assert_raise Jido.Chat.Errors.Validation, fn ->
        Modal.external_select("bad", "Bad", min_query_length: -1)
      end

      assert_raise Jido.Chat.Errors.Validation, fn ->
        Card.external_select("bad", timeout_ms: 0)
      end
    end
  end

  describe "modal inputs" do
    test "date and number constructors validate portable boundaries" do
      date =
        Modal.date_input("start_date", "Start date",
          value: ~D[2026-08-20],
          min_date: ~D[2026-01-01],
          max_date: "2026-12-31",
          required: true
        )

      number =
        Modal.number_input("amount", "Amount",
          value: 12.5,
          min_value: 0,
          max_value: 100,
          step: 0.5
        )

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

    test "submitted date and number values normalize to strings at the event boundary" do
      event =
        ModalSubmitEvent.new(%{
          callback_id: "report",
          values: %{
            "day" => ~D[2026-08-20],
            "count" => 12.5,
            "nested" => %{"page" => 2, "enabled" => true}
          }
        })

      assert event.values == %{
               "day" => "2026-08-20",
               "count" => "12.5",
               "nested" => %{"page" => "2", "enabled" => true}
             }
    end
  end

  describe "typed options loading" do
    test "input, output, groups, error, and timeout are typed" do
      event =
        OptionsLoadEvent.new(%{
          "adapter_name" => "options_test",
          "action_id" => "assignee",
          "query" => "ad",
          "limit" => 250_000
        })

      assert event.adapter_name == :options_test
      assert event.limit == 250_000

      assert {:ok,
              %OptionsLoadResult{
                options: [%OptionsLoadOption{label: "Ada"}],
                option_groups: [%OptionsLoadOptionGroup{label: "Teams"}]
              }} = Adapter.load_options(OptionsAdapter, event)

      assert %OptionsLoadError{kind: :error, code: "upstream"} =
               OptionsLoadError.new(%{code: "upstream", message: "Not available"})

      assert %OptionsLoadError{kind: :timeout, timeout_ms: 1_500, retryable: true} =
               OptionsLoadError.timeout(1_500)

      timeout_event =
        OptionsLoadEvent.new(%{action_id: "assignee", query: "timeout", timeout_ms: 40})

      assert {:error, %OptionsLoadError{kind: :timeout, timeout_ms: 40}} =
               Adapter.load_options(OptionsAdapter, timeout_event)

      error = OptionsLoadError.new(%{code: "upstream", message: "Not available"})
      timeout = OptionsLoadError.timeout(1_500)

      assert %OptionsLoadError{kind: :error} =
               error |> OptionsLoadError.to_map() |> Jido.Chat.Serialization.revive()

      assert %OptionsLoadError{kind: :timeout} =
               timeout |> OptionsLoadError.to_map() |> Jido.Chat.Serialization.revive()
    end

    test "adapter callbacks cannot exceed the resolved options-load timeout" do
      event =
        OptionsLoadEvent.new(%{
          action_id: "assignee",
          query: "slow",
          timeout_ms: 500,
          raw: %{test_pid: self()}
        })

      assert {:error, %OptionsLoadError{kind: :timeout, timeout_ms: 100}} =
               Adapter.load_options(OptionsAdapter, event, timeout_ms: 100)

      assert_receive {:options_load_started, worker}
      refute Process.alive?(worker)
      refute_receive :options_load_completed, 20
    end

    test "options-load envelopes route through the typed adapter callback" do
      chat = Jido.Chat.new(adapters: %{options_test: OptionsAdapter})

      envelope =
        EventEnvelope.new(%{
          adapter_name: :options_test,
          event_type: :options_load,
          payload: %{action_id: "assignee", query: "ad"}
        })

      assert {:ok, ^chat, %EventEnvelope{payload: %OptionsLoadResult{}} = routed} =
               Jido.Chat.process_event(chat, :options_test, envelope)

      assert %EventEnvelope{payload: %OptionsLoadResult{}} =
               routed |> EventEnvelope.to_map() |> EventEnvelope.from_map()

      timeout =
        EventEnvelope.new(%{
          adapter_name: :options_test,
          event_type: :options_load,
          payload: %{action_id: "assignee", query: "timeout", timeout_ms: 40}
        })

      assert {:error, %OptionsLoadError{kind: :timeout, timeout_ms: 40}} =
               Jido.Chat.process_event(chat, :options_test, timeout)
    end

    test "invalid output, error, and timeout boundaries fail" do
      assert_raise Jido.Chat.Errors.Validation, fn ->
        OptionsLoadResult.new(%{options: [%{label: "Missing value"}]})
      end

      assert_raise Jido.Chat.Errors.Validation, fn -> OptionsLoadError.timeout(0) end

      assert_raise Jido.Chat.Errors.Validation, fn ->
        OptionsLoadEvent.new(%{action_id: "assignee", query: "", limit: 0})
      end
    end
  end

  describe "serialization and capabilities" do
    test "string-key card and modal maps normalize all new element kinds" do
      card =
        Card.new(%{
          "components" => [
            %{
              "kind" => "bar_chart",
              "data" => [%{"label" => "Ready", "value" => 3}]
            },
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

    test "new elements and options-load types serialize and revive" do
      card =
        Card.new(%{
          components: [
            Card.pie_chart([{"Ready", 3}]),
            Card.external_select("assignee", options: [Card.select_option("Ada", "ada")])
          ]
        })

      modal =
        Modal.new(%{
          title: "Report",
          elements: [
            Modal.date_input("day", "Day"),
            Modal.number_input("count", "Count"),
            Modal.external_select("assignee", "Assignee")
          ]
        })

      event =
        OptionsLoadEvent.new(%{
          adapter: OptionsAdapter,
          action_id: "assignee",
          query: "ad"
        })

      result = OptionsLoadResult.new(%{options: [%{label: "Ada", value: "ada"}]})

      assert %Card{components: [%Card.Component{data: [%ChartData{}]}, _]} =
               card |> Card.to_map() |> Card.from_map()

      assert %Modal{} = modal |> Modal.to_map() |> Modal.from_map()

      assert %OptionsLoadEvent{adapter: OptionsAdapter} =
               Jido.Chat.Serialization.revive(OptionsLoadEvent.to_map(event))

      assert %OptionsLoadResult{} = Jido.Chat.Serialization.revive(OptionsLoadResult.to_map(result))

      envelope = EventEnvelope.new(%{event_type: :options_load, payload: event})

      assert %EventEnvelope{event_type: :options_load, payload: %OptionsLoadEvent{}} =
               envelope |> EventEnvelope.to_map() |> EventEnvelope.from_map()
    end

    test "capability statuses include native, fallback, and unsupported new elements" do
      matrix = Adapter.capability_matrix(OptionsAdapter)

      assert CapabilityMatrix.status(matrix, :card_charts) == :fallback
      assert CapabilityMatrix.status(matrix, :modal_date_input) == :native
      assert CapabilityMatrix.status(matrix, :modal_number_input) == :native
      assert CapabilityMatrix.status(matrix, :external_select) == :native
      assert CapabilityMatrix.status(matrix, :unknown_element) == :unsupported
      assert :link_action_ids in Jido.Chat.Capabilities.all()
    end
  end
end
