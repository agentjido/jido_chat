defmodule Jido.Chat.Attachment do
  @moduledoc """
  Normalized outbound attachment used by post payloads and sent-message handles.
  """

  alias Jido.Chat.Content.{Audio, File, Image, Video}
  alias Jido.Chat.{FileUpload, Media}

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

  @type input ::
          t()
          | FileUpload.t()
          | Media.t()
          | Image.t()
          | Audio.t()
          | Video.t()
          | File.t()
          | map()
          | String.t()

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Attachment."
  def schema, do: @schema

  @doc "Creates an attachment struct from normalized map input."
  def new(%__MODULE__{} = attachment), do: attachment

  def new(attrs) when is_map(attrs),
    do: attrs |> normalize_map() |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))

  @doc "Normalizes supported outbound attachment inputs into a canonical attachment struct."
  @spec normalize(input()) :: t()
  def normalize(%__MODULE__{} = attachment), do: attachment

  def normalize(%FileUpload{} = file_upload) do
    new(Map.from_struct(file_upload))
  end

  def normalize(%Media{} = media) do
    metadata = media.metadata || %{}
    {path, metadata} = pop_metadata(metadata, :path)
    {data, metadata} = pop_metadata(metadata, :data)

    new(%{
      kind: media.kind,
      url: media.url,
      path: path,
      data: data,
      media_type: media.media_type,
      filename: media.filename,
      size_bytes: media.size_bytes,
      width: media.width,
      height: media.height,
      duration: media.duration,
      metadata: metadata
    })
  end

  def normalize(%Image{} = image) do
    new(%{
      kind: :image,
      url: image.url,
      data: image.data,
      media_type: image.media_type,
      width: image.width,
      height: image.height,
      metadata: compact_metadata(%{alt_text: image.alt_text})
    })
  end

  def normalize(%Audio{} = audio) do
    new(%{
      kind: :audio,
      url: audio.url,
      data: audio.data,
      media_type: audio.media_type,
      duration: audio.duration,
      metadata: compact_metadata(%{transcript: audio.transcript})
    })
  end

  def normalize(%Video{} = video) do
    new(%{
      kind: :video,
      url: video.url,
      data: video.data,
      media_type: video.media_type,
      width: video.width,
      height: video.height,
      duration: video.duration,
      metadata: compact_metadata(%{thumbnail_url: video.thumbnail_url})
    })
  end

  def normalize(%File{} = file) do
    new(%{
      kind: infer_kind(file.media_type, file.filename, file.url),
      url: file.url,
      data: file.data,
      media_type: file.media_type,
      filename: file.filename,
      size_bytes: file.size
    })
  end

  def normalize(attrs) when is_map(attrs), do: new(attrs)

  def normalize(reference) when is_binary(reference) do
    new(%{
      kind: infer_kind(nil, filename_from_reference(reference), reference),
      url: if(remote_reference?(reference), do: reference, else: nil),
      path: if(remote_reference?(reference), do: nil, else: reference),
      filename: filename_from_reference(reference)
    })
  end

  @doc "Normalizes a list of attachment inputs."
  @spec normalize_many([input()]) :: [t()]
  def normalize_many(attachments) when is_list(attachments),
    do: Enum.map(attachments, &normalize/1)

  defp normalize_map(attrs) do
    metadata =
      attrs
      |> metadata_from_attrs()
      |> merge_extra_metadata(attrs)

    media_type =
      attrs[:media_type] || attrs["media_type"] || attrs[:mime_type] || attrs["mime_type"]

    filename = attrs[:filename] || attrs["filename"] || attrs[:name] || attrs["name"]
    url = attrs[:url] || attrs["url"]
    path = attrs[:path] || attrs["path"]

    %{
      kind:
        normalize_kind(attrs[:kind] || attrs["kind"] || attrs[:type] || attrs["type"]) ||
          infer_kind(media_type, filename, url || path),
      url: url,
      path: path,
      data: attrs[:data] || attrs["data"],
      media_type: media_type,
      filename: filename || filename_from_reference(url || path),
      size_bytes: attrs[:size_bytes] || attrs["size_bytes"] || attrs[:size] || attrs["size"],
      width: attrs[:width] || attrs["width"],
      height: attrs[:height] || attrs["height"],
      duration: attrs[:duration] || attrs["duration"],
      metadata: metadata
    }
  end

  defp metadata_from_attrs(attrs) do
    attrs[:metadata] || attrs["metadata"] || %{}
  end

  defp merge_extra_metadata(metadata, attrs) do
    metadata
    |> maybe_put_metadata(:alt_text, attrs[:alt_text] || attrs["alt_text"])
    |> maybe_put_metadata(:transcript, attrs[:transcript] || attrs["transcript"])
    |> maybe_put_metadata(:thumbnail_url, attrs[:thumbnail_url] || attrs["thumbnail_url"])
  end

  defp maybe_put_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_metadata(metadata, key, value), do: Map.put(metadata, key, value)

  defp compact_metadata(entries) do
    entries
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp pop_metadata(metadata, key) when is_map(metadata) do
    atom_value = Map.get(metadata, key)
    string_key = Atom.to_string(key)
    string_value = Map.get(metadata, string_key)

    value = atom_value || string_value
    next_metadata = metadata |> Map.delete(key) |> Map.delete(string_key)

    {value, next_metadata}
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

  defp infer_kind(media_type, filename, reference) do
    cond do
      is_binary(media_type) and String.starts_with?(media_type, "image/") -> :image
      is_binary(media_type) and String.starts_with?(media_type, "audio/") -> :audio
      is_binary(media_type) and String.starts_with?(media_type, "video/") -> :video
      extension_kind(filename || reference) != :file -> extension_kind(filename || reference)
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

  defp filename_from_reference(nil), do: nil

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
