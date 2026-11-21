defmodule Jido.Chat.Signal.AttachmentRef do
  @moduledoc false

  @doc false
  @spec refs(term()) :: {:ok, [String.t()]} | {:error, term()}
  def refs(attachments) when is_list(attachments) do
    Enum.reduce_while(attachments, {:ok, []}, fn attachment, {:ok, acc} ->
      case ref(attachment) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, _reason} = error -> error
    end
  end

  def refs(other), do: {:error, {:invalid_attachments, other}}

  @doc false
  @spec ref(term()) :: {:ok, String.t()} | {:error, term()}
  def ref(%{path: path}) when is_binary(path), do: {:ok, path}
  def ref(%{"path" => path}) when is_binary(path), do: {:ok, path}

  def ref(%{data: data} = attachment) when is_binary(data),
    do: {:ok, data_uri(attachment)}

  def ref(%{"data" => data} = attachment) when is_binary(data),
    do: {:ok, data_uri(attachment)}

  def ref(%{url: url}) when is_binary(url), do: remote_attachment_error(url)
  def ref(%{"url" => url}) when is_binary(url), do: remote_attachment_error(url)

  def ref(value) when is_binary(value) do
    if remote?(value), do: remote_attachment_error(value), else: {:ok, value}
  end

  def ref(other), do: {:error, {:invalid_attachment, other}}

  defp remote?(value), do: String.starts_with?(value, ["http://", "https://"])

  defp remote_attachment_error(value), do: {:error, {:unsupported_remote_attachment, value}}

  defp data_uri(%{data: "data:" <> _ = data}), do: data
  defp data_uri(%{"data" => "data:" <> _ = data}), do: data

  defp data_uri(attachment) do
    data = field(attachment, :data)
    media_type = field(attachment, :media_type) || "application/octet-stream"
    filename = field(attachment, :filename) || "attachment"

    "data:#{media_type};filename=#{filename};base64,#{data}"
  end

  defp field(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
