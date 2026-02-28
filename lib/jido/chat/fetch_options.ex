defmodule Jido.Chat.FetchOptions do
  @moduledoc """
  Canonical options for paginated history fetch operations.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              cursor: Zoi.string() |> Zoi.nullish(),
              limit: Zoi.integer() |> Zoi.default(50),
              direction: Zoi.enum([:forward, :backward]) |> Zoi.default(:backward),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for FetchOptions."
  def schema, do: @schema

  @doc "Builds typed fetch options from keyword/map/struct input."
  def new(%__MODULE__{} = opts), do: opts
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()
  def new(opts) when is_map(opts), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, opts)

  @doc "Converts typed options into keyword options for adapter callbacks."
  @spec to_keyword(t()) :: keyword()
  def to_keyword(%__MODULE__{} = opts) do
    []
    |> maybe_kw(:cursor, opts.cursor)
    |> Keyword.put(:limit, opts.limit)
    |> Keyword.put(:direction, opts.direction)
  end

  defp maybe_kw(keyword, _key, nil), do: keyword
  defp maybe_kw(keyword, key, value), do: Keyword.put(keyword, key, value)
end
