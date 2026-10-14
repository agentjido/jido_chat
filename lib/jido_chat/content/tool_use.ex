defmodule Jido.Chat.Content.ToolUse do
  @moduledoc """
  Tool use content block for messages.

  Represents a request to invoke a tool/action. This maps to the LLM's
  tool_use blocks and integrates with jido_action for execution.

  ## Fields

  - `id` - Unique identifier for this tool invocation (used to correlate with ToolResult)
  - `name` - The name of the tool/action to invoke
  - `input` - The input parameters for the tool as a map

  ## Example

      ToolUse.new("call_123", "get_weather", %{location: "San Francisco"})
      #=> %ToolUse{type: :tool_use, id: "call_123", name: "get_weather", input: %{location: "San Francisco"}}
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              type: Zoi.literal(:tool_use) |> Zoi.default(:tool_use),
              id: Zoi.string(),
              name: Zoi.string(),
              input: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for ToolUse content"
  def schema, do: @schema

  @doc """
  Creates a new tool use content block.

  ## Parameters

  - `id` - Unique identifier for this tool invocation
  - `name` - The name of the tool/action to invoke
  - `input` - The input parameters for the tool (default: %{})

  ## Examples

      iex> ToolUse.new("call_1", "search", %{query: "elixir"})
      %ToolUse{type: :tool_use, id: "call_1", name: "search", input: %{query: "elixir"}}
  """
  def new(id, name, input \\ %{}) when is_binary(id) and is_binary(name) and is_map(input) do
    %__MODULE__{id: id, name: name, input: input}
  end
end
