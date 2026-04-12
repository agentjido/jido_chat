defmodule Jido.Chat.Media do
  @moduledoc """
  Normalized media entry used in `Jido.Chat.Incoming`.
  """

  alias Jido.Chat.Content.{Audio, File, Image, Video}

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
  @type input :: t() | Image.t() | Audio.t() | Video.t() | File.t() | map() | String.t()

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Media."
  def schema, do: @schema

  @doc "Creates a media struct from map input."
  def new(%__MODULE__{} = media), do: media

  def new(attrs) when is_map(attrs),
    do: attrs |> normalize_map() |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))

  @doc "Normalizes supported attachment inputs into a canonical media struct."
  @spec normalize(input()) :: t()
  def normalize(%__MODULE__{} = media), do: media

  def normalize(%Image{} = image) do
    new(%{
      kind: :image,
      url: image.url,
      media_type: image.media_type,
      width: image.width,
      height: image.height,
      metadata: compact_metadata(%{data: image.data, alt_text: image.alt_text})
    })
  end

  def normalize(%Audio{} = audio) do
    new(%{
      kind: :audio,
      url: audio.url,
      media_type: audio.media_type,
      duration: audio.duration,
      metadata: compact_metadata(%{data: audio.data, transcript: audio.transcript})
    })
  end

  def normalize(%Video{} = video) do
    new(%{
      kind: :video,
      url: video.url,
      media_type: video.media_type,
      width: video.width,
      height: video.height,
      duration: video.duration,
      metadata:
        compact_metadata(%{
          data: video.data,
          thumbnail_url: video.thumbnail_url
        })
    })
  end

  def normalize(%File{} = file) do
    new(%{
      kind: infer_kind(file.media_type, file.filename, file.url),
      url: file.url,
      media_type: file.media_type,
      filename: file.filename,
      size_bytes: file.size,
      metadata: compact_metadata(%{data: file.data})
    })
  end

  def normalize(attrs) when is_map(attrs), do: new(attrs)

  def normalize(reference) when is_binary(reference) do
    new(%{
      kind: infer_kind(nil, filename_from_reference(reference), reference),
      url: if(remote_reference?(reference), do: reference, else: nil),
      filename: filename_from_reference(reference),
      metadata:
        compact_metadata(%{
          path: if(remote_reference?(reference), do: nil, else: reference)
        })
    })
  end

  @doc "Normalizes a list of attachments into canonical media structs."
  @spec normalize_many([input()]) :: [t()]
  def normalize_many(media) when is_list(media), do: Enum.map(media, &normalize/1)

  defp normalize_map(attrs) do
    metadata =
      attrs[:metadata] || attrs["metadata"] ||
        %{}
        |> merge_extra_metadata(attrs)

    media_type =
      attrs[:media_type] || attrs["media_type"] || attrs[:mime_type] || attrs["mime_type"]

    filename = attrs[:filename] || attrs["filename"] || attrs[:name] || attrs["name"]
    url = attrs[:url] || attrs["url"]

    %{
      kind:
        normalize_kind(attrs[:kind] || attrs["kind"] || attrs[:type] || attrs["type"]) ||
          infer_kind(media_type, filename, url),
      url: url,
      media_type: media_type,
      filename: filename,
      size_bytes: attrs[:size_bytes] || attrs["size_bytes"] || attrs[:size] || attrs["size"],
      width: attrs[:width] || attrs["width"],
      height: attrs[:height] || attrs["height"],
      duration: attrs[:duration] || attrs["duration"],
      metadata: metadata
    }
  end

  defp merge_extra_metadata(metadata, attrs) do
    metadata
    |> maybe_put_metadata(:data, attrs[:data] || attrs["data"])
    |> maybe_put_metadata(:alt_text, attrs[:alt_text] || attrs["alt_text"])
    |> maybe_put_metadata(:transcript, attrs[:transcript] || attrs["transcript"])
    |> maybe_put_metadata(:thumbnail_url, attrs[:thumbnail_url] || attrs["thumbnail_url"])
    |> maybe_put_metadata(:path, attrs[:path] || attrs["path"])
  end

  defp maybe_put_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_metadata(metadata, key, value), do: Map.put(metadata, key, value)

  defp compact_metadata(entries) do
    entries
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_kind(kind) when kind in [:image, :audio, :video, :file], do: kind

  defp normalize_kind(kind) when is_binary(kind) do
    case kind do
      "image" -> :image
      "audio" -> :audio
      "video" -> :video
      "file" -> :file
      _ -> nil
    end
  end

  defp normalize_kind(_kind), do: nil

  defp infer_kind(media_type, filename, url) do
    cond do
      is_binary(media_type) and String.starts_with?(media_type, "image/") -> :image
      is_binary(media_type) and String.starts_with?(media_type, "audio/") -> :audio
      is_binary(media_type) and String.starts_with?(media_type, "video/") -> :video
      extension_kind(filename || url) != :file -> extension_kind(filename || url)
      true -> :file
    end
  end

  defp extension_kind(nil), do: :file

  defp extension_kind(value) when is_binary(value) do
    case value |> Path.extname() |> String.downcase() do
      ext when ext in [".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg"] -> :image
      ext when ext in [".mp3", ".wav", ".ogg", ".m4a", ".flac", ".aac"] -> :audio
      ext when ext in [".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v"] -> :video
      _ -> :file
    end
  end

  defp filename_from_reference(reference) when is_binary(reference) do
    case remote_reference?(reference) do
      true ->
        reference
        |> URI.parse()
        |> Map.get(:path)
        |> basename_or_nil()

      false ->
        basename_or_nil(reference)
    end
  end

  defp basename_or_nil(nil), do: nil
  defp basename_or_nil(""), do: nil

  defp basename_or_nil(path) do
    case Path.basename(path) do
      "." -> nil
      "/" -> nil
      value -> value
    end
  end

  defp remote_reference?(reference) when is_binary(reference) do
    case URI.parse(reference) do
      %URI{scheme: scheme} when is_binary(scheme) and scheme != "" -> true
      _ -> false
    end
  end
end
