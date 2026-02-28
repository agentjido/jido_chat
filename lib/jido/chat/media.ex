defmodule Jido.Chat.Media do
  @moduledoc """
  Normalized media entry used in `Jido.Chat.Incoming`.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              kind: Zoi.enum([:image, :audio, :video, :file]) |> Zoi.default(:file),
              url: Zoi.string() |> Zoi.nullish(),
              media_type: Zoi.string() |> Zoi.nullish(),
              filename: Zoi.string() |> Zoi.nullish(),
              size_bytes: Zoi.integer() |> Zoi.nullish(),
              width: Zoi.integer() |> Zoi.nullish(),
              height: Zoi.integer() |> Zoi.nullish(),
              duration: Zoi.integer() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Media."
  def schema, do: @schema

  @doc "Creates a media struct from map input."
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)
end
