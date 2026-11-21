defmodule Jido.Chat.Telegram.Webhook do
  @moduledoc "Pure webhook header verification. The host owns HTTP responses and delivery."
  alias Jido.Chat.Client

  @doc "Checks headers against the private secret captured in the Client. No I/O occurs."
  @spec verify(Client.t(), map() | list()) :: :ok | {:error, atom()}
  def verify(%Client{credentials: %{secret_token: expected}}, headers)
      when is_binary(expected) and byte_size(expected) > 0 do
    actual =
      Enum.find_value(headers, fn {key, value} ->
        if String.downcase(to_string(key)) == "x-telegram-bot-api-secret-token", do: value
      end)

    if is_binary(actual) and byte_size(actual) == byte_size(expected) and :crypto.hash_equals(actual, expected),
      do: :ok,
      else: {:error, :invalid_webhook_secret}
  end

  def verify(_, _), do: {:error, :missing_webhook_secret}
end
