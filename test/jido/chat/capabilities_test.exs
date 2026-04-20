defmodule Jido.Chat.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Capabilities, PostPayload, Postable}
  alias Jido.Chat.Content.{Audio, Image, Text, ToolResult, ToolUse}

  test "supports?/2 and all/0" do
    assert Capabilities.supports?([:text, :image], :image)
    refute Capabilities.supports?([:text], :image)
    assert :file in Capabilities.all()
    assert :multi_file in Capabilities.all()
    assert :cards in Capabilities.all()
    refute :message_edit in Capabilities.all()
  end

  test "content_requires/1" do
    assert Capabilities.content_requires(%Text{text: "hi"}) == [:text]
    assert Capabilities.content_requires(%Image{url: "https://example.com/i.png"}) == [:image]
    assert Capabilities.content_requires(%Audio{url: "https://example.com/a.mp3"}) == [:audio]
    assert Capabilities.content_requires(%ToolUse{id: "1", name: "test"}) == [:tool_use]
    assert Capabilities.content_requires(%ToolResult{tool_use_id: "1", content: "ok"}) == [:text]
  end

  test "can_deliver?/2 and content filtering" do
    content = [
      %Text{text: "hi"},
      %Image{url: "https://example.com/i.png"},
      %Audio{url: "https://example.com/a.mp3"}
    ]

    assert Capabilities.can_deliver?([:text, :image], %Text{text: "hi"})
    refute Capabilities.can_deliver?([:text], %Image{url: "https://example.com/i.png"})

    assert [%Text{}, %Image{}] = Capabilities.filter_content(content, [:text, :image])
    assert [%Audio{}] = Capabilities.unsupported_content(content, [:text, :image])
  end

  test "can_deliver?/2 handles outbound post payloads" do
    assert Capabilities.can_deliver?(
             [:text, :file],
             Postable.text("hello", files: ["/tmp/report.pdf"])
           )

    refute Capabilities.can_deliver?(
             [:text, :file],
             Postable.text("hello", files: ["/tmp/report.pdf", "/tmp/other.pdf"])
           )

    assert Capabilities.can_deliver?(
             [:text],
             PostPayload.new(%{kind: :card, card: %{title: "Card"}, fallback_text: "fallback"})
           )

    refute Capabilities.can_deliver?(
             [:text],
             PostPayload.new(%{kind: :stream, stream: ["hello"]})
           )
  end

  test "channel_capabilities/1 defaults to [:text] for adapters without an explicit matrix" do
    defmodule AdapterWithoutCapabilities do
      @behaviour Jido.Chat.Adapter

      @impl true
      def channel_type, do: :test

      @impl true
      def transform_incoming(_), do: {:error, :not_implemented}

      @impl true
      def send_message(_, _, _), do: {:error, :not_implemented}
    end

    assert Capabilities.channel_capabilities(AdapterWithoutCapabilities) == [:text, :streaming]
  end

  test "channel_capabilities/1 derives delivery support from adapter capability matrices" do
    defmodule AdapterWithThreading do
      @behaviour Jido.Chat.Adapter

      @impl true
      def channel_type, do: :threaded

      @impl true
      def post_message(_, _, _), do: {:error, :not_implemented}

      @impl true
      def capabilities do
        %{
          send_message: :native,
          post_message: :native,
          cards: :native,
          modals: :native,
          open_thread: :native,
          list_threads: :native,
          add_reaction: :native,
          remove_reaction: :native,
          start_typing: :fallback,
          stream: :fallback
        }
      end

      @impl true
      def transform_incoming(_), do: {:error, :not_implemented}

      @impl true
      def send_message(_, _, _), do: {:error, :not_implemented}
    end

    assert Capabilities.channel_capabilities(AdapterWithThreading) == [
             :text,
             :image,
             :audio,
             :video,
             :file,
             :multi_file,
             :cards,
             :modals,
             :threads,
             :reactions,
             :typing,
             :streaming
           ]
  end

  test "channel_capabilities/1 preserves legacy list-based adapter capabilities" do
    defmodule AdapterWithLegacyListCapabilities do
      @behaviour Jido.Chat.Adapter

      @impl true
      def channel_type, do: :legacy_caps

      @impl true
      def capabilities, do: [:text, :image, :threads]

      @impl true
      def transform_incoming(_), do: {:error, :not_implemented}

      @impl true
      def send_message(_, _, _), do: {:error, :not_implemented}
    end

    assert Capabilities.channel_capabilities(AdapterWithLegacyListCapabilities) == [
             :text,
             :image,
             :threads
           ]
  end
end
