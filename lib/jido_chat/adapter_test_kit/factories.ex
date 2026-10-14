defmodule Jido.Chat.AdapterTestKit.Factories do
  @moduledoc "Deterministic domain values and typed Signal fixtures for provider-free tests."

  @doc "Builds a retained author value."
  @spec author(map()) :: Jido.Chat.Author.t()
  def author(overrides \\ %{}),
    do: Jido.Chat.Author.new(Map.merge(%{user_id: "actor-1", user_name: "test-user"}, overrides))

  @doc "Builds a retained media value."
  @spec media(map()) :: Jido.Chat.Media.t()
  def media(overrides \\ %{}),
    do: Jido.Chat.Media.new(Map.merge(%{kind: :image, url: "https://example.com/image.png"}, overrides))

  @doc "Builds a retained domain message."
  @spec message(map()) :: Jido.Chat.Message.t()
  def message(overrides \\ %{}),
    do: Jido.Chat.Message.new(Map.merge(%{id: "message-1", text: "hello", external_room_id: "room-1"}, overrides))

  @doc "Builds a private webhook request/control value."
  @spec webhook_request(map()) :: Jido.Chat.WebhookRequest.t()
  def webhook_request(overrides \\ %{}),
    do: Jido.Chat.WebhookRequest.new(Map.merge(%{payload: %{}, method: "POST", path: "/", headers: %{}}, overrides))

  @doc "Builds a retained outbound domain payload."
  @spec post_payload(map()) :: Jido.Chat.PostPayload.t()
  def post_payload(overrides \\ %{}), do: Jido.Chat.PostPayload.new(Map.merge(%{kind: :text, text: "hello"}, overrides))

  @doc "Builds a typed message fact with fixed delivery/item and context identities."
  @spec message_received(Jido.Chat.Binding.t(), map()) :: Jido.Signal.t()
  def message_received(binding, overrides \\ %{}) do
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

    Jido.Chat.Signal.MessageReceived.new!(data,
      source: binding.source,
      subject: Jido.Chat.Signal.Identity.conversation_subject(binding.id, data["room_id"])
    )
  end

  @doc "Builds a typed request from a checked definition module and string-key data."
  @spec request(module(), map()) :: Jido.Signal.t()
  def request(definition, data), do: definition.new!(data)

  @doc "Builds one valid operation fixture with private resources owned by this caller."
  @spec operation_request(Jido.Chat.Binding.t(), atom(), map()) :: Jido.Signal.t()
  def operation_request(binding, operation, overrides \\ %{}) do
    {_type, {definition, ^operation, fields, _shape, _schema}} =
      Enum.find(Jido.Chat.Operations.Definitions.all(), fn {_type, {_definition, name, _fields, _shape, _schema}} ->
        name == operation
      end)

    values = %{
      "request_id" => "fixture:" <> Atom.to_string(operation),
      "room_id" => "room/1",
      "user_id" => "actor-1",
      "message_id" => "message-1",
      "text" => "hello",
      "reaction" => "👍",
      "interaction_id" => "interaction-1",
      "query" => "a",
      "content" => %{"kind" => "text", "text" => "hello"}
    }

    data =
      Enum.reduce(fields, Map.take(values, ["request_id" | fields]), fn field, data ->
        if field in ["resource_ref", "media_ref", "modal"] and not Map.has_key?(overrides, field) do
          {kind, value} = fixture_resource(operation, field)
          {:ok, ref} = Jido.Chat.put_resource(binding, kind, value)
          Map.put(data, field, ref)
        else
          data
        end
      end)

    definition.new!(Map.merge(data, overrides))
  end

  defp fixture_resource(:stream, _field), do: {"stream", ["hello", " world"]}
  defp fixture_resource(_operation, "media_ref"), do: {"media", %{"id" => "provider-media-1"}}
  defp fixture_resource(_operation, "modal"), do: {"modal", Jido.Chat.Modal.new(%{title: "Fixture"})}

  defp fixture_resource(_operation, _field),
    do: {"file", Jido.Chat.FileUpload.new(%{filename: "fixture.txt", data: "Zml4dHVyZQ==", media_type: "text/plain"})}
end
