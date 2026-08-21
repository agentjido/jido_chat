defmodule Jido.Chat.OptionsLoadEvent do
  @moduledoc """
  Normalized request to load options for an external or dynamic select.
  """

  alias Jido.Chat.{Author, Wire}

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              adapter: Zoi.any() |> Zoi.nullish(),
              adapter_name: Zoi.atom() |> Zoi.nullish(),
              action_id: Zoi.string() |> Zoi.min(1),
              query: Zoi.string() |> Zoi.default(""),
              limit: Zoi.integer() |> Zoi.nullish(),
              timeout_ms: Zoi.integer() |> Zoi.nullish(),
              thread_id: Zoi.string() |> Zoi.nullish(),
              channel_id: Zoi.string() |> Zoi.nullish(),
              message_id: Zoi.string() |> Zoi.nullish(),
              view_id: Zoi.string() |> Zoi.nullish(),
              user: Zoi.struct(Author) |> Zoi.nullish(),
              raw: Zoi.map() |> Zoi.default(%{}),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )
          |> Zoi.refine({__MODULE__, :validate, []})

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for an options-load event."
  def schema, do: @schema

  @doc "Creates a normalized options-load event."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = event), do: event

  def new(attrs) when is_map(attrs) do
    attrs
    |> Map.put_new(:id, attrs[:id] || attrs["id"] || Jido.Chat.ID.generate!())
    |> normalize_adapter_name()
    |> normalize_author()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc false
  def validate(_schema, %__MODULE__{limit: limit}) when is_integer(limit) and limit < 1,
    do: {:error, "limit must be greater than zero"}

  def validate(_schema, %__MODULE__{timeout_ms: timeout_ms})
      when is_integer(timeout_ms) and timeout_ms < 1,
      do: {:error, "timeout_ms must be greater than zero"}

  def validate(_schema, %__MODULE__{}), do: :ok

  @doc "Serializes the options-load event."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    event
    |> Map.from_struct()
    |> Map.update!(:adapter, &Wire.encode_module/1)
    |> Wire.to_plain()
    |> Map.put("__type__", "options_load_event")
  end

  @doc "Builds an options-load event from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    adapter = map[:adapter] || map["adapter"]

    map
    |> Map.drop(["__type__", :__type__, "adapter", :adapter])
    |> Map.put(:adapter, Wire.decode_module(adapter))
    |> new()
  end

  defp normalize_author(%{user: %Author{}} = attrs), do: attrs
  defp normalize_author(%{"user" => %Author{}} = attrs), do: attrs

  defp normalize_author(attrs) do
    case attrs[:user] || attrs["user"] do
      %{} = user -> attrs |> Map.delete("user") |> Map.put(:user, Author.new(user))
      _ -> attrs
    end
  end

  defp normalize_adapter_name(attrs) do
    case attrs[:adapter_name] || attrs["adapter_name"] do
      name when is_binary(name) ->
        attrs |> Map.delete("adapter_name") |> Map.put(:adapter_name, String.to_existing_atom(name))

      _ ->
        attrs
    end
  rescue
    ArgumentError -> attrs
  end
end
