defmodule Jido.Chat.Content.Audio do
  @moduledoc """
  Audio content block for messages.

  Represents an audio attachment (voice messages, audio files).

  ## Fields

  - `url` - URL to the audio file (optional if data is provided)
  - `data` - Base64-encoded audio data (optional if url is provided)
  - `media_type` - MIME type (e.g., "audio/mp3", "audio/ogg")
  - `duration` - Duration in seconds (optional)
  - `transcript` - Text transcript of the audio (optional)

  ## Examples

      Audio.new("https://example.com/voice.ogg")
      Audio.new("https://example.com/voice.ogg", media_type: "audio/ogg", duration: 15)
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              type: Zoi.literal(:audio) |> Zoi.default(:audio),
              url: Zoi.string() |> Zoi.nullish(),
              data: Zoi.string() |> Zoi.nullish(),
              media_type: Zoi.string() |> Zoi.nullish(),
              duration: Zoi.integer() |> Zoi.nullish(),
              transcript: Zoi.string() |> Zoi.nullish()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Audio content"
  def schema, do: @schema

  @doc """
  Creates a new audio content block from a URL.

  ## Options

  - `:media_type` - MIME type of the audio
  - `:duration` - Duration in seconds
  - `:transcript` - Text transcript
  """
  def new(url, opts \\ []) when is_binary(url) do
    %__MODULE__{
      url: url,
      media_type: Keyword.get(opts, :media_type),
      duration: Keyword.get(opts, :duration),
      transcript: Keyword.get(opts, :transcript)
    }
  end

  @doc """
  Creates a new audio content block from base64-encoded data.
  """
  def from_base64(data, media_type, opts \\ []) when is_binary(data) and is_binary(media_type) do
    %__MODULE__{
      data: data,
      media_type: media_type,
      duration: Keyword.get(opts, :duration),
      transcript: Keyword.get(opts, :transcript)
    }
  end
end
