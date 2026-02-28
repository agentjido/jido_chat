defmodule Jido.Chat.ThreadPage do
  @moduledoc """
  Canonical page of thread summaries.
  """

  alias Jido.Chat.ThreadSummary

  @schema Zoi.struct(
            __MODULE__,
            %{
              threads: Zoi.array(Zoi.struct(ThreadSummary)) |> Zoi.default([]),
              next_cursor: Zoi.string() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for ThreadPage."
  def schema, do: @schema

  @doc "Creates a canonical thread page and normalizes summary entries."
  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_threads()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  defp normalize_threads(attrs) do
    threads = attrs[:threads] || attrs["threads"] || []

    normalized =
      Enum.map(threads, fn
        %ThreadSummary{} = summary -> summary
        map when is_map(map) -> ThreadSummary.new(map)
        other -> other
      end)

    Map.put(attrs, :threads, normalized)
  end
end
