defmodule Jido.Chat.Content.File do
  @moduledoc """
  File attachment content block for messages.

  Represents a generic file attachment (documents, audio, video, etc.).

  ## Fields

  - `url` - URL to the file (optional if data is provided)
  - `data` - Base64-encoded file data (optional if url is provided)
  - `media_type` - MIME type (e.g., "application/pdf", "audio/mp3")
  - `filename` - Original filename
  - `size` - File size in bytes (optional)

  ## Examples

      File.new("https://example.com/doc.pdf", "document.pdf")
      File.new("https://example.com/doc.pdf", "document.pdf", media_type: "application/pdf")
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              type: Zoi.literal(:file) |> Zoi.default(:file),
              url: Zoi.string() |> Zoi.nullish(),
              data: Zoi.string() |> Zoi.nullish(),
              media_type: Zoi.string() |> Zoi.nullish(),
              filename: Zoi.string() |> Zoi.nullish(),
              size: Zoi.integer() |> Zoi.nullish()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for File content"
  def schema, do: @schema

  @doc """
  Creates a new file content block from a URL.

  ## Options

  - `:media_type` - MIME type of the file
  - `:size` - File size in bytes
  """
  def new(url, filename, opts \\ []) when is_binary(url) and is_binary(filename) do
    %__MODULE__{
      url: url,
      filename: filename,
      media_type: Keyword.get(opts, :media_type),
      size: Keyword.get(opts, :size)
    }
  end

  @doc """
  Creates a new file content block from base64-encoded data.

  ## Parameters

  - `data` - Base64-encoded file data
  - `filename` - Original filename
  - `media_type` - MIME type
  - `opts` - Additional options (size)
  """
  def from_base64(data, filename, media_type, opts \\ [])
      when is_binary(data) and is_binary(filename) and is_binary(media_type) do
    %__MODULE__{
      data: data,
      filename: filename,
      media_type: media_type,
      size: Keyword.get(opts, :size)
    }
  end
end
