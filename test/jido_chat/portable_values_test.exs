defmodule Jido.Chat.PortableValuesTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{
    Actor,
    AI,
    Card,
    Content,
    FileSource,
    IdentitySource,
    Markdown,
    Media,
    Message,
    Modal,
    Post,
    Principal,
    ResourceRef,
    StreamChunk
  }

  alias Jido.Chat.Errors.Validation

  test "actor and resource values accept wire maps and round trip" do
    actor =
      Actor.new(%{
        "id" => "user-1",
        "display_name" => "Ada",
        "is_bot" => true
      })

    assert actor.kind == :bot
    assert actor.display_name == "Ada"
    assert Actor.from_map(Actor.to_map(actor)) == actor

    reference = ResourceRef.new(%{"id" => "file-1", "client_id" => "support", "kind" => "file"})
    assert ResourceRef.from_map(ResourceRef.to_map(reference)) == reference
  end

  test "file sources require exactly one portable source" do
    reference = ResourceRef.new(%{id: "file-1", client_id: "support", kind: :file})
    source = FileSource.reference(reference, filename: "report.txt")

    assert FileSource.from_map(FileSource.to_map(source)) == source

    assert_raise Jido.Chat.Errors.Validation, fn ->
      FileSource.new(%{kind: :url, url: "https://example.test/file", content_base64: "YQ=="})
    end
  end

  test "posts preserve rich content through portable maps" do
    reference = ResourceRef.new(%{id: "image-1", client_id: "support", kind: :media})

    media =
      Media.new(%{
        kind: :image,
        source: FileSource.reference(reference),
        alt_text: "Status chart"
      })

    post =
      Post.new(%{
        content: [
          Content.text("Ready"),
          Content.markdown("**Ship it**"),
          Content.media(media)
        ],
        mentions: ["operator"],
        reply_to_id: "message-1"
      })

    assert Post.from_map(Post.to_map(post)) == post
    assert Post.fallback_text(post) == "Ready\n**Ship it**\nStatus chart"
  end

  test "messages convert to portable AI history" do
    message =
      Message.new(%{
        id: "message-2",
        room_id: "room-1",
        actor: Actor.new(%{id: "assistant", kind: :agent}),
        role: :assistant,
        content: [Content.text("Done")]
      })

    assert Message.from_map(Message.to_map(message)) == message
    assert AI.to_messages([message]) == [%{"role" => "assistant", "content" => "Done"}]
  end

  test "portable values reject process-local terms before serialization" do
    source = FileSource.url("https://example.test/file")
    actor = Actor.new(%{id: "actor-1"})

    builders = [
      fn -> Actor.new(%{id: "actor-1", metadata: %{owner: self()}}) end,
      fn -> ResourceRef.new(%{id: "file-1", client_id: "client-1", kind: :file, metadata: %{owner: self()}}) end,
      fn -> FileSource.new(%{kind: :url, url: "https://example.test/file", metadata: %{owner: self()}}) end,
      fn -> Media.new(%{kind: :file, source: source, metadata: %{owner: self()}}) end,
      fn -> Content.new(%{kind: :text, text: "Hello", metadata: %{owner: self()}}) end,
      fn -> Post.text("Hello", metadata: %{owner: self()}) end,
      fn ->
        Message.new(%{
          id: "message-1",
          room_id: "room-1",
          actor: actor,
          content: [Content.text("Hello")],
          metadata: %{owner: self()}
        })
      end,
      fn -> Principal.new(%{id: "principal-1", kind: :human, attributes: %{owner: self()}}) end,
      fn ->
        IdentitySource.new(%{
          provider: "test",
          account_id: "account-1",
          external_id: "external-1",
          metadata: %{owner: self()}
        })
      end,
      fn -> Card.new(%{title: "Status", metadata: %{owner: self()}}) end,
      fn -> Card.ChartData.new(%{label: "Ready", value: 1, metadata: %{owner: self()}}) end,
      fn -> Card.ChartSeries.new(%{name: "Ready", values: [1], metadata: %{owner: self()}}) end,
      fn -> Card.Component.new(%{kind: :text, text: "Ready", metadata: %{owner: self()}}) end,
      fn -> Markdown.root([], metadata: %{owner: self()}) end,
      fn -> Markdown.Node.new(%{type: :text, text: "Ready", metadata: %{owner: self()}}) end,
      fn -> Modal.new(%{title: "Status", metadata: %{owner: self()}}) end,
      fn -> Modal.Element.new(%{kind: :text_input, id: "status", metadata: %{owner: self()}}) end,
      fn -> StreamChunk.new(%{kind: :data, payload: %{owner: self()}}) end
    ]

    Enum.each(builders, fn builder ->
      assert_raise Validation, builder
    end)

    assert_raise Validation, fn -> Content.tool_result("call-1", fn -> :local end) end
  end

  test "portable values preserve supported conversions and reject key collisions" do
    actor =
      Actor.new(%{
        id: "actor-1",
        metadata: %{
          datetime: ~U[2026-01-01 00:00:00Z],
          naive: ~N[2026-01-01 00:00:00],
          set: MapSet.new(["one"]),
          tuple: {"one", "two"},
          matcher: ~r/hello/i
        }
      })

    assert Actor.to_map(actor)["metadata"] == %{
             "datetime" => "2026-01-01T00:00:00Z",
             "naive" => "2026-01-01T00:00:00",
             "set" => ["one"],
             "tuple" => ["one", "two"],
             "matcher" => %{"source" => "hello", "opts" => Regex.opts(~r/hello/i)}
           }

    collision = Map.put(%{:trace => "atom"}, "trace", "string")

    assert_raise Validation, fn ->
      Actor.new(%{id: "actor-1", metadata: collision})
    end

    assert_raise Validation, fn ->
      Actor.new(%{:id => "atom", "id" => "string"})
    end

    for invalid_key <- [1, 1.0] do
      assert_raise Validation, fn ->
        Actor.new(%{id: "actor-1", metadata: %{invalid_key => "value"}})
      end

      collision = %{invalid_key => "number", to_string(invalid_key) => "string"}

      assert_raise Validation, fn ->
        Actor.new(%{id: "actor-1", metadata: collision})
      end
    end
  end

  test "rendering revival rejects type marker collisions before removal" do
    values = [
      {Card, Card.new(%{title: "Card"})},
      {Card.ChartData, Card.ChartData.new(%{label: "Ready", value: 1})},
      {Card.ChartSeries, Card.ChartSeries.new(%{name: "Ready", values: [1]})},
      {Card.Component, Card.Component.new(%{kind: :text, text: "Ready"})},
      {Markdown, Markdown.root([])},
      {Markdown.Node, Markdown.Node.new(%{type: :text, text: "Ready"})},
      {Modal, Modal.new(%{title: "Modal"})},
      {Modal.Element, Modal.Element.new(%{kind: :text_input, id: "input"})},
      {StreamChunk, StreamChunk.text("Ready")}
    ]

    Enum.each(values, fn {module, value} ->
      map = module.to_map(value) |> Map.put(:__type__, "conflict")

      assert_raise Validation, fn -> module.from_map(map) end
    end)
  end

  test "rendering helpers reject option key collisions before selection" do
    opts = %{"metadata" => %{"source" => "string"}, metadata: %{"source" => "atom"}}

    builders = [
      fn -> Card.text("Ready", opts) end,
      fn -> Markdown.root([], opts) end,
      fn -> Modal.text_input("input", "Input", opts) end,
      fn -> StreamChunk.text("Ready", opts) end
    ]

    Enum.each(builders, fn builder ->
      assert_raise Validation, builder
    end)
  end

  test "content accepts only the fields for its selected kind" do
    invalid_values = [
      %{kind: :text, text: "plain", markdown: "**hidden**"},
      %{kind: :tool_use, tool_call_id: "call-1", tool_name: "lookup", tool_input: %{}, tool_result: "hidden"},
      %{kind: :text, text: "plain", tool_error: true}
    ]

    Enum.each(invalid_values, fn attrs ->
      assert_raise Validation, fn -> Content.new(attrs) end
    end)

    assert Content.tool_result("call-1", "failed", true).tool_error
  end

  test "Runtime room schemas reject unsafe portable terms" do
    safe_post = Post.to_map(Post.text("Hello"))
    unsafe_post = put_in(safe_post["metadata"]["owner"], self())

    safe_message =
      Message.new(%{
        id: "message-1",
        room_id: "room-1",
        actor: Actor.new(%{id: "actor-1"}),
        content: [Content.text("Hello")]
      })
      |> Message.to_map()

    unsafe_message = put_in(safe_message["metadata"]["owner"], self())

    assert {:ok, _post} = Zoi.parse(Jido.Chat.Runtime.Signal.Room.post_schema(), safe_post)
    assert {:error, _errors} = Zoi.parse(Jido.Chat.Runtime.Signal.Room.post_schema(), unsafe_post)
    assert {:ok, _message} = Zoi.parse(Jido.Chat.Runtime.Signal.Room.message_schema(), safe_message)
    assert {:error, _errors} = Zoi.parse(Jido.Chat.Runtime.Signal.Room.message_schema(), unsafe_message)
  end
end
