defmodule Jido.Chat.Slack.Webhook do
  @moduledoc "Pure Slack webhook verification and decoding helpers. The host owns HTTP."

  alias Jido.Chat.Client
  alias Jido.Chat.Slack.InteractionResponse

  @default_tolerance 300

  @doc "Checks the exact request body with the signing secret in the Client."
  @spec verify(Client.t(), binary(), map() | list(), keyword()) :: :ok | {:error, atom()}
  def verify(client, body, headers, opts \\ [])

  def verify(%Client{credentials: %{signing_secret: secret}}, body, headers, opts)
      when is_binary(secret) and secret != "" and is_binary(body) and is_list(opts) do
    timestamp = header(headers, "x-slack-request-timestamp")
    signature = header(headers, "x-slack-signature")
    now = Keyword.get(opts, :now, System.system_time(:second))
    tolerance = Keyword.get(opts, :tolerance, @default_tolerance)

    with {sent_at, ""} <- Integer.parse(to_string(timestamp)),
         true <- is_integer(now) and is_integer(tolerance) and tolerance >= 0,
         true <- abs(now - sent_at) <= tolerance,
         expected <-
           "v0=" <>
             Base.encode16(:crypto.mac(:hmac, :sha256, secret, "v0:#{timestamp}:#{body}"),
               case: :lower
             ),
         true <- secure_equal(signature, expected) do
      :ok
    else
      _ -> {:error, :invalid_signature}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  def verify(_, _, _, _), do: {:error, :missing_signing_secret}

  @doc "Decodes one JSON or form-encoded Slack request body."
  @spec decode(binary(), map() | list()) :: {:ok, map()} | {:error, atom()}
  def decode(body, headers \\ [])

  def decode(body, headers) when is_binary(body) do
    content_type = String.downcase(header(headers, "content-type") || "")

    cond do
      String.contains?(content_type, "application/json") -> decode_json(body)
      String.contains?(content_type, "application/x-www-form-urlencoded") -> decode_form(body)
      true -> decode_json(body)
    end
  end

  def decode(_, _), do: {:error, :invalid_body}

  @doc "Builds an optional plain HTTP response value for an interaction."
  def response(result, opts \\ []), do: InteractionResponse.webhook_response(result, opts)

  defp decode_json(body) do
    case Jason.decode(body) do
      {:ok, value} when is_map(value) -> {:ok, value}
      _ -> {:error, :invalid_body}
    end
  end

  defp decode_form(body) do
    form = URI.decode_query(body)

    case form["payload"] do
      payload when is_binary(payload) -> decode_json(payload)
      _ -> {:ok, form}
    end
  rescue
    _ -> {:error, :invalid_body}
  end

  defp header(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(to_string(key)) == name do
        case value do
          [first | _] -> first
          other -> other
        end
      end
    end)
  end

  defp secure_equal(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right),
       do: :crypto.hash_equals(left, right)

  defp secure_equal(_, _), do: false
end
