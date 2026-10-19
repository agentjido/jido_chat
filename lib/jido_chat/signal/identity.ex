defmodule Jido.Chat.Signal.Identity do
  @moduledoc """
  Builds stable provider context identities from configured client and room keys.

  Keys use UTF-8 bytes encoded as unpadded Base64url. Display names, provider
  tokens, transport modules, and runtime room identities do not form these keys.
  """

  @doc "Returns the opaque source for a configured client key."
  @spec client_source(String.t()) :: String.t()
  def client_source(client_id), do: "urn:jido:chat:client:" <> encode(client_id, 128)

  @doc "Returns the primary conversation subject scoped by a client key."
  @spec conversation_subject(String.t(), String.t()) :: String.t()
  def conversation_subject(client_id, external_room_id) do
    "conversation:" <> encode(client_id, 128) <> ":" <> encode(external_room_id, 2_048)
  end

  defp encode(value, max_bytes)
       when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= max_bytes do
    if String.valid?(value), do: Base.url_encode64(value, padding: false), else: invalid_key()
  end

  defp encode(_value, _max_bytes), do: invalid_key()
  defp invalid_key, do: raise(ArgumentError, "expected a non-empty UTF-8 identity key within its byte limit")
end
