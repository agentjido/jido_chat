defmodule Jido.Chat.Content.Text do
  @moduledoc """
  Text content block for messages.

  This is the simplest content type - just plain text.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              type: Zoi.literal(:text) |> Zoi.default(:text),
              text: Zoi.string()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Text content"
  def schema, do: @schema

  @doc "Creates a new text content block"
  def new(text) when is_binary(text) do
    %__MODULE__{text: text}
  end
end
