defmodule Jido.Chat.Content.Video do
  @moduledoc """
  Video content block for messages.

  Represents a video attachment.

  ## Fields

  - `url` - URL to the video file (optional if data is provided)
  - `data` - Base64-encoded video data (optional if url is provided)
  - `media_type` - MIME type (e.g., "video/mp4")
  - `duration` - Duration in seconds (optional)
  - `width` - Video width in pixels (optional)
  - `height` - Video height in pixels (optional)
  - `thumbnail_url` - URL to thumbnail image (optional)

  ## Examples

      Video.new("https://example.com/clip.mp4")
      Video.new("https://example.com/clip.mp4", media_type: "video/mp4", duration: 30)
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              type: Zoi.literal(:video) |> Zoi.default(:video),
              url: Zoi.string() |> Zoi.nullish(),
              data: Zoi.string() |> Zoi.nullish(),
              media_type: Zoi.string() |> Zoi.nullish(),
              duration: Zoi.integer() |> Zoi.nullish(),
              width: Zoi.integer() |> Zoi.nullish(),
              height: Zoi.integer() |> Zoi.nullish(),
              thumbnail_url: Zoi.string() |> Zoi.nullish()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Video content"
  def schema, do: @schema

  @doc """
  Creates a new video content block from a URL.

  ## Options

  - `:media_type` - MIME type of the video
  - `:duration` - Duration in seconds
  - `:width` - Video width in pixels
  - `:height` - Video height in pixels
  - `:thumbnail_url` - URL to thumbnail image
  """
  def new(url, opts \\ []) when is_binary(url) do
    %__MODULE__{
      url: url,
      media_type: Keyword.get(opts, :media_type),
      duration: Keyword.get(opts, :duration),
      width: Keyword.get(opts, :width),
      height: Keyword.get(opts, :height),
      thumbnail_url: Keyword.get(opts, :thumbnail_url)
    }
  end

  @doc """
  Creates a new video content block from base64-encoded data.
  """
  def from_base64(data, media_type, opts \\ []) when is_binary(data) and is_binary(media_type) do
    %__MODULE__{
      data: data,
      media_type: media_type,
      duration: Keyword.get(opts, :duration),
      width: Keyword.get(opts, :width),
      height: Keyword.get(opts, :height),
      thumbnail_url: Keyword.get(opts, :thumbnail_url)
    }
  end
end
