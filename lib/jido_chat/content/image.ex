defmodule Jido.Chat.Content.Image do
  @moduledoc """
  Image content block for messages.

  Represents an image attachment in a message. Supports both URL-based
  and base64-encoded images.

  ## Fields

  - `url` - URL to the image (optional if data is provided)
  - `data` - Base64-encoded image data (optional if url is provided)
  - `media_type` - MIME type (e.g., "image/png", "image/jpeg")
  - `alt_text` - Alternative text description
  - `width` - Image width in pixels (optional)
  - `height` - Image height in pixels (optional)

  ## Examples

      Image.new("https://example.com/photo.jpg")
      Image.new("https://example.com/photo.jpg", media_type: "image/jpeg", alt_text: "A photo")
      Image.from_base64(base64_data, "image/png")
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              type: Zoi.literal(:image) |> Zoi.default(:image),
              url: Zoi.string() |> Zoi.nullish(),
              data: Zoi.string() |> Zoi.nullish(),
              media_type: Zoi.string() |> Zoi.nullish(),
              alt_text: Zoi.string() |> Zoi.nullish(),
              width: Zoi.integer() |> Zoi.nullish(),
              height: Zoi.integer() |> Zoi.nullish()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Image content"
  def schema, do: @schema

  @doc """
  Creates a new image content block from a URL.

  ## Options

  - `:media_type` - MIME type of the image
  - `:alt_text` - Alternative text description
  - `:width` - Image width in pixels
  - `:height` - Image height in pixels
  """
  def new(url, opts \\ []) when is_binary(url) do
    %__MODULE__{
      url: url,
      media_type: Keyword.get(opts, :media_type),
      alt_text: Keyword.get(opts, :alt_text),
      width: Keyword.get(opts, :width),
      height: Keyword.get(opts, :height)
    }
  end

  @doc """
  Creates a new image content block from base64-encoded data.

  ## Parameters

  - `data` - Base64-encoded image data
  - `media_type` - MIME type (required for base64 images)
  - `opts` - Additional options (alt_text, width, height)
  """
  def from_base64(data, media_type, opts \\ []) when is_binary(data) and is_binary(media_type) do
    %__MODULE__{
      data: data,
      media_type: media_type,
      alt_text: Keyword.get(opts, :alt_text),
      width: Keyword.get(opts, :width),
      height: Keyword.get(opts, :height)
    }
  end
end
