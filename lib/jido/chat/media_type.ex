defmodule Jido.Chat.MediaType do
  @moduledoc """
  Resolves media types without applying a provider-independent default.

  Adapters should use evidence in this order:

  1. A valid MIME value declared by the provider.
  2. A default that the provider contract guarantees for the downloadable file.
  3. A file signature, when the bytes have already been downloaded.
  4. A filename or URL extension as a best-effort hint.

  `resolve/2` follows this order. A provider default is never added unless the
  caller supplies `:provider_default`. Normalization and MIME resolution do not
  change media bytes.
  """

  @type kind :: :image | :audio | :video | :file

  @extension_media_types %{
    ".aac" => "audio/aac",
    ".avi" => "video/x-msvideo",
    ".avif" => "image/avif",
    ".bmp" => "image/bmp",
    ".csv" => "text/csv",
    ".flac" => "audio/flac",
    ".gif" => "image/gif",
    ".gz" => "application/gzip",
    ".heic" => "image/heic",
    ".heif" => "image/heif",
    ".html" => "text/html",
    ".jpeg" => "image/jpeg",
    ".jpg" => "image/jpeg",
    ".json" => "application/json",
    ".m4a" => "audio/mp4",
    ".m4v" => "video/x-m4v",
    ".md" => "text/markdown",
    ".mkv" => "video/x-matroska",
    ".mov" => "video/quicktime",
    ".mp3" => "audio/mpeg",
    ".mp4" => "video/mp4",
    ".ogg" => "audio/ogg",
    ".pdf" => "application/pdf",
    ".png" => "image/png",
    ".svg" => "image/svg+xml",
    ".tif" => "image/tiff",
    ".tiff" => "image/tiff",
    ".txt" => "text/plain",
    ".wav" => "audio/wav",
    ".webm" => "video/webm",
    ".webp" => "image/webp",
    ".zip" => "application/zip"
  }

  @doc """
  Resolves the best available MIME value.

  Supported options are `:provider_default`, `:data`, `:filename`, `:url`, and
  `:path`. Filename and reference values are hints and have the lowest priority.
  """
  @spec resolve(term(), keyword()) :: String.t() | nil
  def resolve(provider_value, opts \\ []) when is_list(opts) do
    normalize(provider_value) ||
      normalize(Keyword.get(opts, :provider_default)) ||
      sniff(Keyword.get(opts, :data)) ||
      from_filename(reference(opts))
  end

  @doc "Returns a normalized MIME value or `nil` for blank and invalid values."
  @spec normalize(term()) :: String.t() | nil
  def normalize(value) when is_binary(value) do
    media_type =
      value
      |> String.split(";", parts: 2)
      |> hd()
      |> String.trim()
      |> String.downcase()

    if Regex.match?(~r/^[a-z0-9!#$&^_.+-]+\/[a-z0-9!#$&^_.+-]+$/, media_type),
      do: media_type,
      else: nil
  end

  def normalize(_value), do: nil

  @doc "Returns a MIME hint from a filename, path, or URL extension."
  @spec from_filename(term()) :: String.t() | nil
  def from_filename(value) when is_binary(value) do
    value
    |> reference_path()
    |> Path.extname()
    |> String.downcase()
    |> then(&Map.get(@extension_media_types, &1))
  end

  def from_filename(_value), do: nil

  @doc "Detects common binary formats from their file signatures."
  @spec sniff(term()) :: String.t() | nil
  def sniff(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: "image/jpeg"
  def sniff(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>), do: "image/png"
  def sniff(<<"GIF87a", _rest::binary>>), do: "image/gif"
  def sniff(<<"GIF89a", _rest::binary>>), do: "image/gif"
  def sniff(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>), do: "image/webp"
  def sniff(<<"BM", _rest::binary>>), do: "image/bmp"
  def sniff(<<"%PDF-", _rest::binary>>), do: "application/pdf"
  def sniff(<<0x1F, 0x8B, _rest::binary>>), do: "application/gzip"

  def sniff(<<"PK", marker::binary-size(2), _rest::binary>>)
      when marker in [<<3, 4>>, <<5, 6>>, <<7, 8>>],
      do: "application/zip"

  def sniff(_data), do: nil

  @doc "Returns the canonical media kind from MIME data or a reference hint."
  @spec kind(term(), term()) :: kind()
  def kind(media_type, reference \\ nil) do
    case normalize(media_type) || from_filename(reference) do
      "image/" <> _rest -> :image
      "audio/" <> _rest -> :audio
      "video/" <> _rest -> :video
      _other -> :file
    end
  end

  defp reference(opts) do
    Keyword.get(opts, :filename) ||
      Keyword.get(opts, :url) ||
      Keyword.get(opts, :path)
  end

  defp reference_path(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, path: path} when is_binary(scheme) and is_binary(path) -> path
      _other -> value
    end
  end
end
