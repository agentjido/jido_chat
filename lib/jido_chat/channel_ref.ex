defmodule Jido.Chat.ChannelRef do
  @moduledoc """
  Retained channel identity and metadata record.

  Provider operations use typed requests through `Jido.Chat.execute/2`.
  """
  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              adapter_name: Zoi.atom(),
              adapter: Zoi.any(),
              external_id: Zoi.any(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the channel reference schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates a channel reference record."
  @spec new(map()) :: t()
  def new(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)

  @doc "Returns a stored display name. Renames do not change identity."
  @spec name(t()) :: String.t() | nil
  def name(channel),
    do: channel.metadata[:name] || channel.metadata["name"] || channel.metadata[:title] || channel.metadata["title"]

  @doc "Renders an existing user key as a provider mention value."
  @spec mention_user(t(), String.t() | integer()) :: String.t()
  def mention_user(%__MODULE__{adapter_name: :discord}, user), do: "<@#{user}>"
  def mention_user(_channel, user), do: "@#{user}"

  @doc "Serializes a retained domain reference."
  @spec to_map(t()) :: map()
  def to_map(channel) do
    channel
    |> Map.from_struct()
    |> Map.update!(:adapter, &Wire.encode_module/1)
    |> Wire.to_plain()
    |> Map.put("__type__", "channel")
  end

  @doc "Builds a domain reference from stored data."
  @spec from_map(map()) :: t()
  def from_map(map) do
    adapter = map[:adapter] || map["adapter"]

    map
    |> Map.drop(["__type__", :__type__, "adapter", :adapter])
    |> Map.put(:adapter, Wire.decode_module(adapter))
    |> new()
  end
end
