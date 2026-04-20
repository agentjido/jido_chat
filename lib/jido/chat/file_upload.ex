defmodule Jido.Chat.FileUpload do
  @moduledoc """
  Canonical outbound file upload request used by posting and upload helpers.
  """

  alias Jido.Chat.{Attachment, Wire}

  @schema Zoi.struct(
            __MODULE__,
            %{
              kind: Zoi.enum([:image, :audio, :video, :file]) |> Zoi.default(:file),
              url: Zoi.string() |> Zoi.nullish(),
              path: Zoi.string() |> Zoi.nullish(),
              data: Zoi.string() |> Zoi.nullish(),
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
  @type input :: t() | Attachment.input()

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for FileUpload."
  def schema, do: @schema

  @doc "Creates a file upload request from normalized map input."
  def new(%__MODULE__{} = file_upload), do: file_upload

  def new(attrs) when is_map(attrs),
    do: attrs |> normalize_map() |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))

  @doc "Normalizes supported upload inputs into a canonical file upload struct."
  @spec normalize(input()) :: t()
  def normalize(%__MODULE__{} = file_upload), do: file_upload

  def normalize(%Attachment{} = attachment), do: from_attachment(attachment)
  def normalize(input), do: input |> Attachment.normalize() |> from_attachment()

  @doc "Normalizes a list of file upload inputs."
  @spec normalize_many([input()]) :: [t()]
  def normalize_many(files) when is_list(files), do: Enum.map(files, &normalize/1)

  @doc "Serializes a file upload into a plain map with type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = file_upload) do
    file_upload
    |> Map.from_struct()
    |> Wire.to_plain()
    |> Map.put("__type__", "file_upload")
  end

  @doc "Builds a file upload from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()

  defp from_attachment(%Attachment{} = attachment) do
    attachment
    |> Map.from_struct()
    |> new()
  end

  defp normalize_map(attrs) do
    attrs
    |> Map.drop(["__type__", :__type__])
    |> Enum.into(%{}, fn
      {:type, value} -> {:kind, value}
      {"type", value} -> {:kind, value}
      pair -> pair
    end)
  end
end
