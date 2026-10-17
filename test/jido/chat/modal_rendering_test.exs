defmodule Jido.Chat.ModalRenderingTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Modal
  alias Jido.Chat.Modal.Element

  test "modal controls retain accessible labels, options and nested groups" do
    option = Modal.select_option("One", "1", %{"help_text" => "Help"})
    group = Modal.select_option_group("Group", [option], %{"id" => "group"})

    elements = [
      Modal.text_input("text", "Notes", multiline: true, required: true, help_text: "Add notes."),
      Modal.text_input("plain", "Name"),
      Modal.date_input("date", "Date", min_date: ~D[2026-01-01], max_date: ~D[2026-12-31]),
      Modal.number_input("number", "Count", min_value: 0, max_value: 10, step: 0.5),
      Modal.select("select", "Pick", [option]),
      Element.new(%{kind: :radio_select, id: "radio", label: "Radio"}),
      Modal.external_select("external", "Search", %{"option_groups" => [group], "options_source" => "external"}),
      Modal.dynamic_select("dynamic", "Dynamic", fallback_text: "Custom"),
      group,
      option
    ]

    modal = Modal.new(%{id: "modal", title: "Form", elements: elements})
    assert modal.callback_id == "modal"

    assert Modal.fallback_text(modal) ==
             "Form\nNotes (multiline text input, required). Add notes.\nName (text input).\nDate (date input). Minimum date: 2026-01-01. Maximum date: 2026-12-31.\nCount (number input). Minimum: 0. Maximum: 10. Step: 0.5.\nPick (select input).\nRadio (radio select input).\nSearch (external select input).\nCustom\nGroup: One.\nOne"

    payload = Modal.to_adapter_payload(modal)
    assert payload["fallback_text"] == Modal.fallback_text(modal)
    external = Enum.at(payload["elements"], 6)
    assert external["option_groups"] |> hd() |> Map.fetch!("options") |> hd() |> Map.fetch!("value") == "1"
    assert Modal.to_map(Modal.from_map(Modal.to_map(modal))) == Modal.to_map(modal)
    assert Modal.new(modal) == modal
    assert Element.from_map(Element.to_map(option)) == option
  end

  test "external source normalization rejects unknown values and retains known values" do
    for source <- [:external, :dynamic, "dynamic", nil] do
      element = Modal.external_select("pick", "Pick", %{options_source: source})
      assert element.options_source in [:external, :dynamic]
    end

    assert_raise Jido.Chat.Errors.Validation, fn ->
      Modal.external_select("pick", "Pick", options_source: "unknown-source")
    end

    assert Modal.fallback_text(Modal.new(%{title: "Empty"})) == "Empty"
    assert Zoi.parse(Modal.schema(), %{}) |> elem(0) == :error
  end
end
