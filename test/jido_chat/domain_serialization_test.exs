defmodule Jido.Chat.RenderingSerializationTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.{Card, Markdown, Modal}

  test "string-key cards normalize markdown before fallback rendering" do
    markdown = Markdown.root([Markdown.paragraph("Ready")])

    for input <- ["Ready", markdown, Markdown.to_map(markdown)] do
      card = Card.new(%{"markdown" => input})
      assert card == Card.new(%{markdown: input})
      assert %Markdown{} = card.markdown
      assert Card.fallback_text(card) == "Ready"
      assert Card.to_adapter_payload(card)["fallback_text"] == "Ready"
      decoded = Card.from_map(Card.to_map(card))
      assert %Markdown{} = decoded.markdown
      assert Card.to_map(decoded) == Card.to_map(card)
      assert Card.fallback_text(decoded) == "Ready"
    end
  end

  test "string-key card components keep typed markdown through serialization and fallback rendering" do
    markdown = Markdown.root([Markdown.paragraph("Ready")])

    for input <- ["Ready", markdown, Markdown.to_map(markdown)] do
      component = Card.Component.new(%{"kind" => "section", "markdown" => input})
      assert component == Card.Component.new(%{kind: :section, markdown: input})
      assert %Markdown{} = component.markdown
      decoded = Card.Component.from_map(Card.Component.to_map(component))
      assert %Markdown{} = decoded.markdown
      assert Card.Component.to_map(decoded) == Card.Component.to_map(component)
      card = Card.new(%{components: [component]})
      assert Card.fallback_text(card) == "Ready"
      decoded_card = Card.from_map(Card.to_map(card))
      assert Card.to_map(decoded_card) == Card.to_map(card)
      assert Card.fallback_text(decoded_card) == "Ready"
    end
  end

  test "deep rendering trees preserve every node and marker through serialization" do
    cases = [
      {Markdown.Node, struct!(Markdown.Node, type: :text, text: "leaf"), :children, %{type: :strong}, "markdown_node"},
      {Card.Component, Card.text("leaf"), :items, %{kind: :section}, "card_component"},
      {Modal.Element, Modal.text_input("leaf", "Name"), :options, %{kind: :select, id: "parent"}, "modal_element"}
    ]

    for {module, leaf, children, attrs, marker} <- cases do
      tree = Enum.reduce(1..64, leaf, fn _, child -> struct!(module, Map.put(attrs, children, [child])) end)
      map = module.to_map(tree)
      assert map["__type__"] == marker
      assert map |> module.from_map() |> module.to_map() == map

      terminal =
        Enum.reduce(1..64, map, fn _, node ->
          assert node["__type__"] == marker
          [child] = node[Atom.to_string(children)]
          child
        end)

      assert terminal == module.to_map(leaf)
    end
  end

  test "serialization rejects invalid nested model values" do
    cases = [
      {Markdown.Node, :children, %{type: :root}, struct!(Markdown.Node, type: :heading, level: -1)},
      {Card.Component, :items, %{kind: :section}, struct!(Card.Component, kind: :table)},
      {Modal.Element, :options, %{kind: :select, id: "parent"},
       struct!(Modal.Element, kind: :text_input, id: "child", step: -1)}
    ]

    for {module, children, attrs, invalid} <- cases do
      tree = struct!(module, Map.put(attrs, children, [invalid]))
      assert_raise Jido.Chat.Errors.Validation, fn -> module.to_map(tree) end
    end
  end
end
