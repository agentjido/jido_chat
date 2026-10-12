defmodule Jido.Chat.Signal.Identity do
  @moduledoc """
  Builds stable provider context identities from configured binding and room keys.

  Keys use UTF-8 bytes encoded as unpadded Base64url. Display names, provider
  tokens, transport modules, and runtime room identities do not form these keys.
  """

  @doc "Returns the opaque source for a configured binding key."
  @spec binding_source(String.t()) :: String.t()
  def binding_source(binding_id), do: "urn:jido:chat:binding:" <> encode(binding_id, 128)

  @doc "Returns the primary conversation subject scoped by a binding key."
  @spec conversation_subject(String.t(), String.t()) :: String.t()
  def conversation_subject(binding_id, external_room_id) do
    "conversation:" <> encode(binding_id, 128) <> ":" <> encode(external_room_id, 2_048)
  end

  defp encode(value, max_bytes)
       when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= max_bytes do
    if String.valid?(value), do: Base.url_encode64(value, padding: false), else: invalid_key()
  end

  defp encode(_value, _max_bytes), do: invalid_key()
  defp invalid_key, do: raise(ArgumentError, "expected a non-empty UTF-8 identity key within its byte limit")
end
