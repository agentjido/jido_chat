defmodule Jido.Chat.Content.ToolResult do
  @moduledoc """
  Tool result content block for messages.

  Represents the result of a tool/action invocation. This maps to the LLM's
  tool_result blocks and contains the output from jido_action execution.

  ## Fields

  - `tool_use_id` - The ID of the ToolUse this result corresponds to
  - `content` - The result content (can be text, structured data, or error info)
  - `is_error` - Whether this result represents an error

  ## Example

      ToolResult.new("call_123", "The weather in San Francisco is 72°F")
      #=> %ToolResult{type: :tool_result, tool_use_id: "call_123", content: "The weather...", is_error: false}

      ToolResult.new("call_456", "Tool not found: unknown_tool", true)
      #=> %ToolResult{type: :tool_result, tool_use_id: "call_456", content: "Tool not found...", is_error: true}
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              type: Zoi.literal(:tool_result) |> Zoi.default(:tool_result),
              tool_use_id: Zoi.string(),
              content: Zoi.any(),
              is_error: Zoi.boolean() |> Zoi.default(false)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for ToolResult content"
  def schema, do: @schema

  @doc """
  Creates a new tool result content block.

  ## Parameters

  - `tool_use_id` - The ID of the ToolUse this result corresponds to
  - `content` - The result content (string, map, or any term)
  - `is_error` - Whether this result represents an error (default: false)

  ## Examples

      iex> ToolResult.new("call_1", %{results: [1, 2, 3]})
      %ToolResult{type: :tool_result, tool_use_id: "call_1", content: %{results: [1, 2, 3]}, is_error: false}

      iex> ToolResult.new("call_2", "Error: timeout", true)
      %ToolResult{type: :tool_result, tool_use_id: "call_2", content: "Error: timeout", is_error: true}
  """
  def new(tool_use_id, content, is_error \\ false)
      when is_binary(tool_use_id) and is_boolean(is_error) do
    %__MODULE__{tool_use_id: tool_use_id, content: content, is_error: is_error}
  end
end
