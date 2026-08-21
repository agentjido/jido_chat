defmodule Jido.Chat.MessageLifecycleEvent do
  @moduledoc false

  alias Jido.Chat.{Author, ChannelRef, Message, Thread, Wire}

  @doc "Normalizes common fields for a typed message lifecycle event."
  @spec normalize(map()) :: map()
  def normalize(attrs) when is_map(attrs) do
    attrs
    |> normalize_adapter()
    |> normalize_author()
    |> normalize_handle(:thread, Thread)
    |> normalize_handle(:channel, ChannelRef)
    |> attach_message_id()
    |> normalize_handle(:message, Message)
  end

  @doc "Serializes a message lifecycle event with the specified type marker."
  @spec to_map(struct(), String.t()) :: map()
  def to_map(event, type) when is_struct(event) and is_binary(type) do
    event
    |> Map.from_struct()
    |> Map.update!(:adapter, &Wire.encode_module/1)
    |> Map.update!(:thread, &serialize_handle(&1, Thread))
    |> Map.update!(:channel, &serialize_handle(&1, ChannelRef))
    |> Map.update!(:message, &serialize_handle(&1, Message))
    |> Wire.to_plain()
    |> Map.put("__type__", type)
  end

  defp normalize_adapter(attrs) do
    case attrs[:adapter] || attrs["adapter"] do
      adapter when is_binary(adapter) ->
        attrs |> Map.delete("adapter") |> Map.put(:adapter, Wire.decode_module(adapter))

      _ ->
        attrs
    end
  end

  defp normalize_author(attrs) do
    author = attrs[:author] || attrs["author"] || attrs[:user] || attrs["user"]

    case author do
      %Author{} = value ->
        attrs
        |> Map.drop(["author", :user, "user"])
        |> Map.put(:author, value)

      %{} = value ->
        attrs
        |> Map.drop(["author", :user, "user"])
        |> Map.put(:author, Author.new(value))

      _ ->
        attrs
    end
  end

  defp normalize_handle(attrs, key, mod) do
    case attrs[key] || attrs[Atom.to_string(key)] do
      %{__struct__: ^mod} = value ->
        attrs |> Map.delete(Atom.to_string(key)) |> Map.put(key, value)

      %{} = value ->
        attrs |> Map.delete(Atom.to_string(key)) |> Map.put(key, mod.from_map(value))

      _ ->
        attrs
    end
  end

  defp attach_message_id(attrs) do
    message = attrs[:message] || attrs["message"]

    message_target_id =
      if is_map(message) do
        Map.get(message, :external_message_id) || Map.get(message, "external_message_id") ||
          Map.get(message, :id) || Map.get(message, "id")
      end

    message_id =
      attrs[:message_id] || attrs["message_id"] || message_target_id

    if is_nil(message_id) do
      attrs
    else
      attrs |> Map.delete("message_id") |> Map.put(:message_id, to_string(message_id))
    end
  end

  defp serialize_handle(nil, _mod), do: nil
  defp serialize_handle(value, mod), do: mod.to_map(value)
end
