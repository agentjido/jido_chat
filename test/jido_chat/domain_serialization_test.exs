defmodule Jido.Chat.RenderingSerializationTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.{Card, Markdown}

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
end
