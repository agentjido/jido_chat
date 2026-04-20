defmodule Jido.Chat.Concurrency do
  @moduledoc """
  Chat-level overlapping-message concurrency configuration.
  """

  @strategies [:reject, :queue, :debounce, :concurrent]

  @schema Zoi.struct(
            __MODULE__,
            %{
              strategy: Zoi.enum(@strategies) |> Zoi.default(:reject),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type strategy :: :reject | :queue | :debounce | :concurrent
  @type t :: unquote(Zoi.type_spec(@schema))
  @type pending_entry :: %{owner: String.t(), strategy: strategy(), metadata: map()}

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for concurrency configuration."
  def schema, do: @schema

  @doc "Creates a normalized concurrency config."
  @spec new(t() | map() | keyword()) :: t()
  def new(%__MODULE__{} = config), do: config
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()
  def new(opts) when is_map(opts), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, opts)
end
