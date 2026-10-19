defmodule Jido.Chat.ModelValidationTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Card, Markdown, Modal, StreamChunk}
  alias Jido.Chat.Errors.Validation

  test "constructors revalidate supplied structs and nested values" do
    node = struct!(Markdown.Node, type: :heading, level: -1)
    component = struct!(Card.Component, kind: :table, columns: ["A"], rows: [[1, 2]])
    element = struct!(Modal.Element, kind: :text_input, id: "input", min_length: 5, max_length: 1)

    invalid = [
      {Markdown.Node, node},
      {Markdown, struct!(Markdown, root: struct!(Markdown.Node, type: :root, children: [node]))},
      {Card.Component, component},
      {Card, struct!(Card, components: [component])},
      {Modal.Element, element},
      {Modal, struct!(Modal, title: "Form", elements: [element])},
      {StreamChunk, struct!(StreamChunk, kind: :unknown)},
      {Card.ChartData, struct!(Card.ChartData, label: "A", value: :invalid)},
      {Card.ChartSeries, struct!(Card.ChartSeries, name: "A", values: ["invalid"])}
    ]

    for {module, value} <- invalid do
      assert_raise Validation, fn -> module.new(value) end
    end
  end
end
