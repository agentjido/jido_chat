defmodule Jido.Chat.Discord.Webhook do
  @moduledoc "Pure Discord interaction signature check. The host owns HTTP and acknowledgements."
  @doc "Check the exact request body with the public key stored in the Client credentials."
  @spec verify(Jido.Chat.Client.t(), binary(), map() | list()) :: :ok | {:error, atom()}
  def verify(%Jido.Chat.Client{credentials: %{public_key: key}}, body, headers)
      when is_binary(key) and is_binary(body) do
    headers = Map.new(headers, fn {key, value} -> {key |> to_string() |> String.downcase(), value} end)

    with timestamp when is_binary(timestamp) <- headers["x-signature-timestamp"],
         signature when is_binary(signature) <- headers["x-signature-ed25519"],
         {:ok, public} when byte_size(public) == 32 <- Base.decode16(key, case: :mixed),
         {:ok, signature} when byte_size(signature) == 64 <- Base.decode16(signature, case: :mixed),
         true <- :crypto.verify(:eddsa, :none, timestamp <> body, signature, [public, :ed25519]) do
      :ok
    else
      _ -> {:error, :invalid_signature}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  def verify(_, _, _), do: {:error, :missing_public_key}
end
