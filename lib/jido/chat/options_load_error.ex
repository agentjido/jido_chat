defmodule Jido.Chat.OptionsLoadError do
  @moduledoc """
  Typed error or timeout from a dynamic select option loader.
  """

  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              kind: Zoi.enum([:error, :timeout]) |> Zoi.default(:error),
              code: Zoi.string() |> Zoi.default("options_load_failed"),
              message: Zoi.string() |> Zoi.default("Options could not be loaded"),
              retryable: Zoi.boolean() |> Zoi.default(false),
              timeout_ms: Zoi.integer() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )
          |> Zoi.refine({__MODULE__, :validate, []})

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for an options-load error."
  def schema, do: @schema

  @doc "Creates an options-load error."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = error), do: error
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)

  @doc "Creates a retryable options-load timeout."
  @spec timeout(pos_integer(), keyword() | map()) :: t()
  def timeout(timeout_ms, opts \\ []) do
    opts = Map.new(opts)

    new(
      Map.merge(opts, %{
        kind: :timeout,
        code: "options_load_timeout",
        message: "Options did not load before the timeout",
        retryable: true,
        timeout_ms: timeout_ms
      })
    )
  end

  @doc false
  def validate(_schema, %__MODULE__{kind: :timeout, timeout_ms: timeout_ms})
      when not is_integer(timeout_ms) or timeout_ms < 1,
      do: {:error, "timeout_ms must be greater than zero for a timeout"}

  def validate(_schema, %__MODULE__{timeout_ms: timeout_ms})
      when is_integer(timeout_ms) and timeout_ms < 1,
      do: {:error, "timeout_ms must be greater than zero"}

  def validate(_schema, %__MODULE__{}), do: :ok

  @doc "Serializes the options-load error."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = error) do
    error
    |> Map.from_struct()
    |> Wire.to_plain()
    |> Map.put("__type__", "options_load_error")
  end

  @doc "Builds an options-load error from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()
end
