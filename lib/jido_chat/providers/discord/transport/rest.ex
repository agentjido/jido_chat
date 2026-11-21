defmodule Jido.Chat.Discord.Transport.REST do
  @moduledoc "Stateless Discord HTTP transport. Each call uses the explicit Client token."
  @behaviour Jido.Chat.Discord.Transport
  @compile {:no_warn_undefined, Req}

  alias Jido.Chat.Providers.Dependencies

  @impl true
  def call(token, method, path, body, opts) do
    with :ok <- Dependencies.req() do
      request(token, method, path, body, opts)
    end
  end

  defp request(token, method, path, body, opts) do
    request = [
      method: method,
      url: "https://discord.com/api/v10" <> path,
      headers: [{"authorization", "Bot " <> token}],
      retry: false,
      redirect: false,
      receive_timeout: Keyword.get(opts, :timeout, 15_000)
    ]

    request =
      case body do
        nil ->
          request

        {:multipart, payload, bytes, filename} ->
          Keyword.put(request, :form_multipart, [
            {"payload_json", Jason.encode!(payload)},
            {"files[0]", {bytes, filename: filename}}
          ])

        value ->
          Keyword.put(request, :json, value)
      end

    request = Keyword.merge(request, Keyword.take(opts, [:adapter, :plug, :connect_options, :finch_private]))

    case Req.request(request) do
      {:ok, %{status: status, body: result}} when status in 200..299 ->
        {:ok, result}

      {:ok, %{status: status, body: result}} ->
        category =
          case status do
            401 -> :unauthorized
            403 -> :forbidden
            404 -> :not_found
            429 -> :rate_limited
            _ -> :provider_failure
          end

        hints =
          case result do
            %{"retry_after" => seconds} when is_number(seconds) and seconds >= 0 ->
              %{retry_after_ms: ceil(seconds * 1000)}

            _ ->
              %{}
          end

        if status < 500, do: {:error, {:rejected, category, hints}}, else: {:error, :provider_failure}

      {:error, _} ->
        {:error, :transport_failure}
    end
  end
end
