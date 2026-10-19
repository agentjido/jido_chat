defmodule Jido.Chat.AdapterTestKit.Factories do
  @moduledoc "Deterministic domain values and typed Signal fixtures for provider-free tests."

  @doc "Builds a typed message fact with fixed delivery/item and context identities."
  @spec message_received(Jido.Chat.Client.t(), map()) :: Jido.Signal.t()
  def message_received(client, overrides \\ %{}) do
    data =
      Map.merge(
        %{
          "item_id" => "item-1",
          "delivery_id" => "delivery-1",
          "room_id" => "room-1",
          "message_id" => "message-1",
          "sender" => %{"id" => "actor-1"},
          "text" => "hello"
        },
        overrides
      )

    Jido.Chat.Signal.Policy.new!(Jido.Chat.Signal.MessageReceived, data,
      source: client.source,
      subject: Jido.Chat.Signal.Identity.conversation_subject(client.id, data["room_id"])
    )
  end

  @doc "Builds a typed request from a checked definition module and string-key data."
  @spec request(module(), map()) :: Jido.Signal.t()
  def request(definition, data), do: Jido.Chat.Signal.Policy.new!(definition, data)

  @doc "Builds one portable request fixture without private resource storage."
  @spec operation_request(Jido.Chat.Client.t(), atom(), map()) :: Jido.Signal.t()
  def operation_request(client, operation, overrides \\ %{}) do
    {_type, {definition, ^operation, fields, _, _}} =
      Enum.find(Jido.Chat.Operations.Definitions.all(), fn {_, {_, name, _, _, _}} -> name == operation end)

    values = %{
      "client_id" => client.id,
      "request_id" => "fixture:" <> Atom.to_string(operation),
      "room_id" => "room/1",
      "user_id" => "actor-1",
      "message_id" => "message-1",
      "text" => "hello",
      "reaction" => "👍",
      "interaction_id" => "interaction-1",
      "query" => "a",
      "content" => %{"kind" => "text", "text" => "hello"},
      "name" => "Support",
      "thread_id" => "thread-1",
      "modal" => %{"title" => "Test"},
      "source" => %{"id" => "file-1", "client_id" => client.id, "kind" => "file"},
      "resource_ref" => %{"id" => "media-1", "client_id" => client.id, "kind" => "media"}
    }

    Jido.Chat.Signal.Policy.new!(
      definition,
      values |> Map.take(["client_id", "request_id" | fields]) |> Map.merge(overrides)
    )
  end
end
