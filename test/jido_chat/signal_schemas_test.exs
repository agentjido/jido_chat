defmodule Jido.Chat.SignalSchemasTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Card, Modal}
  alias Jido.Chat.Signal.Schemas

  test "shared schemas accept representative portable values" do
    reference = %{"id" => "file-1", "client_id" => "client-1", "kind" => "file"}
    actor = %{"id" => "actor-1"}
    media = %{"kind" => "file", "resource_ref" => reference}

    valid = [
      {Schemas.optional_id(), nil},
      {Schemas.reference(), reference},
      {Schemas.file_source(), reference},
      {Schemas.file_source(), %{"content_base64" => "YQ==", "filename" => "a.txt"}},
      {Schemas.keyboard(), %{"rows" => [[%{"text" => "Open", "url" => "https://example.test"}]]}},
      {Schemas.actor(), actor},
      {Schemas.media(), media},
      {Schemas.completion("send", Schemas.result(:message)),
       %{
         "client_id" => "client-1",
         "request_id" => "request-1",
         "operation" => "send",
         "result" => %{"id" => "message-1", "room_id" => "room-1"}
       }},
      {Schemas.result(:acknowledgement), %{"acknowledged" => true}},
      {Schemas.result(:conversation), %{"id" => "room-1", "kind" => "channel"}},
      {Schemas.result(:thread), %{"id" => "thread-1", "room_id" => "room-1"}},
      {Schemas.result(:created_thread), %{"id" => "thread-1", "room_id" => "room-1", "name" => "Help"}},
      {Schemas.result(:user), actor},
      {Schemas.result(:subject), %{"id" => "subject-1", "room_id" => "room-1", "kind" => "message"}},
      {Schemas.result(:participants), %{"participants" => [actor], "complete" => true, "scope" => "all"}},
      {Schemas.result(:resource), %{"content_base64" => "YQ=="}},
      {Schemas.result(:modal), %{"opened" => true}},
      {Schemas.result(:options), %{"options" => [], "complete" => true}},
      {Schemas.result(:message_page), %{"messages" => [], "complete" => true}},
      {Schemas.result(:thread_page), %{"threads" => [], "complete" => true}}
    ]

    Enum.each(valid, fn {schema, value} ->
      assert {:ok, _parsed} = Jido.Joi.parse(schema, value)
    end)
  end

  test "shared schemas reject invalid files, keyboards, and rendering markers" do
    assert {:error, _errors} =
             Jido.Joi.parse(Schemas.file_source(), %{"content_base64" => "not-base64", "filename" => "a.txt"})

    assert {:error, _errors} = Jido.Joi.parse(Schemas.result(:resource), %{"content_base64" => "not-base64"})

    long_value = String.duplicate("x", 65)

    assert {:error, _errors} =
             Jido.Joi.parse(Schemas.keyboard(), %{"rows" => [[%{"text" => "Run", "value" => long_value}]]})

    rows = for row <- 1..13, do: for(column <- 1..8, do: %{"text" => "#{row}:#{column}", "value" => "ok"})
    assert {:error, _errors} = Jido.Joi.parse(Schemas.keyboard(), %{"rows" => rows})

    card = Card.new(%{title: "Status"}) |> Card.to_map()
    modal = Modal.new(%{title: "Confirm"}) |> Modal.to_map()
    assert {:ok, ^card} = Jido.Joi.parse(Schemas.card(), card)
    assert {:ok, ^modal} = Jido.Joi.parse(Schemas.modal(), modal)

    assert {:error, _errors} =
             Jido.Joi.parse(Schemas.card(), Map.put(card, "__type__", "modal"))

    assert {:error, _errors} = Jido.Joi.parse(Schemas.modal(), %{"__type__" => "modal"})

    assert {:error, _reason} =
             Schemas.valid_rendering(%{"__type__" => "modal"}, Card, "card", [])
  end
end
