defmodule Jido.Chat.ModalSubmitEvent do
  @moduledoc """
  Normalized modal submit event payload placeholder for Phase 2.
  """

  alias Jido.Chat.{Author, ChannelRef, Message, Modal, ModalResponse, Thread, Wire}

  @schema Zoi.struct(
            __MODULE__,
            %{
              adapter: Zoi.any() |> Zoi.nullish(),
              adapter_name: Zoi.atom() |> Zoi.nullish(),
              thread_id: Zoi.string() |> Zoi.nullish(),
              channel_id: Zoi.string() |> Zoi.nullish(),
              message_id: Zoi.string() |> Zoi.nullish(),
              callback_id: Zoi.string() |> Zoi.nullish(),
              view_id: Zoi.string() |> Zoi.nullish(),
              trigger_id: Zoi.string() |> Zoi.nullish(),
              private_metadata: Zoi.string() |> Zoi.nullish(),
              values: Zoi.map() |> Zoi.default(%{}),
              user: Zoi.struct(Author) |> Zoi.nullish(),
              thread: Zoi.struct(Thread) |> Zoi.nullish(),
              channel: Zoi.struct(ChannelRef) |> Zoi.nullish(),
              message: Zoi.struct(Message) |> Zoi.nullish(),
              related_thread: Zoi.struct(Thread) |> Zoi.nullish(),
              related_channel: Zoi.struct(ChannelRef) |> Zoi.nullish(),
              related_message: Zoi.struct(Message) |> Zoi.nullish(),
              raw: Zoi.map() |> Zoi.default(%{}),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for ModalSubmitEvent."
  def schema, do: @schema

  @doc "Creates a normalized modal submit event payload."
  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_author()
    |> normalize_handles()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Builds a close response for modal handlers."
  @spec close(keyword() | map()) :: ModalResponse.t()
  def close(opts \\ []), do: ModalResponse.close(opts)

  @doc "Builds a validation error response for modal handlers."
  @spec errors(map(), keyword() | map()) :: ModalResponse.t()
  def errors(errors, opts \\ []), do: ModalResponse.errors(errors, opts)

  @doc "Builds an update response for modal handlers."
  @spec update(Modal.t() | map(), keyword() | map()) :: ModalResponse.t()
  def update(modal, opts \\ []), do: ModalResponse.update(modal, opts)

  @doc "Builds a push response for modal handlers."
  @spec push(Modal.t() | map(), keyword() | map()) :: ModalResponse.t()
  def push(modal, opts \\ []), do: ModalResponse.push(modal, opts)

  @doc "Serializes the modal submit event into a plain map with a type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    event
    |> Map.from_struct()
    |> serialize_handles()
    |> Wire.to_plain()
    |> Map.put("__type__", "modal_submit_event")
  end

  @doc "Builds a modal submit event from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()

  defp normalize_author(%{user: %Author{}} = attrs), do: attrs
  defp normalize_author(%{"user" => %Author{}} = attrs), do: attrs

  defp normalize_author(attrs) do
    case attrs[:user] || attrs["user"] do
      %{} = user -> Map.delete(attrs, "user") |> Map.put(:user, Author.new(user))
      _ -> attrs
    end
  end

  defp normalize_handles(attrs) do
    attrs
    |> normalize_handle(:thread, Thread)
    |> normalize_handle(:channel, ChannelRef)
    |> normalize_handle(:message, Message)
    |> normalize_handle(:related_thread, Thread)
    |> normalize_handle(:related_channel, ChannelRef)
    |> normalize_handle(:related_message, Message)
  end

  defp normalize_handle(attrs, key, mod) do
    case attrs[key] || attrs[Atom.to_string(key)] do
      %{__struct__: ^mod} = value ->
        attrs |> Map.delete(Atom.to_string(key)) |> Map.put(key, value)

      %{} = value ->
        attrs |> Map.delete(Atom.to_string(key)) |> Map.put(key, mod.new(value))

      _ ->
        attrs
    end
  end

  defp serialize_handles(map) do
    map
    |> Map.update!(:adapter, &Wire.encode_module/1)
    |> Map.update!(:thread, fn value -> serialize_handle(value, &Thread.to_map/1) end)
    |> Map.update!(:channel, fn value -> serialize_handle(value, &ChannelRef.to_map/1) end)
    |> Map.update!(:message, fn value -> serialize_handle(value, &Message.to_map/1) end)
    |> Map.update!(:related_thread, fn value -> serialize_handle(value, &Thread.to_map/1) end)
    |> Map.update!(:related_channel, fn value -> serialize_handle(value, &ChannelRef.to_map/1) end)
    |> Map.update!(:related_message, fn value -> serialize_handle(value, &Message.to_map/1) end)
  end

  defp serialize_handle(nil, _fun), do: nil
  defp serialize_handle(value, fun), do: fun.(value)
end
