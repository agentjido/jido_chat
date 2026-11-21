defmodule Jido.Chat.Slack.SocketMode.ReqClient do
  @moduledoc """
  Slack Socket Mode client backed by `Req`.
  """

  @behaviour Jido.Chat.Slack.SocketMode.Client

  alias Jido.Chat.Providers.Dependencies

  @base_url "https://slack.com/api"

  @impl true
  def open_socket(app_token, opts \\ []) when is_binary(app_token) and is_list(opts) do
    req_module = Keyword.get(opts, :req, Req)

    with :ok <- Dependencies.req(req_module) do
      request(req_module, app_token, opts)
    end
  end

  defp request(req_module, app_token, opts) do
    url = api_url(opts)

    request_opts = [
      method: :post,
      url: url,
      headers: [{"authorization", "Bearer #{app_token}"}] ++ normalize_headers(opts[:headers])
    ]

    case req_module.request(request_opts) do
      {:ok, %{__struct__: Req.Response, status: status, body: body}} when status in 200..299 ->
        normalize_response(body)

      {:ok, %{__struct__: Req.Response, status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_response(%{"ok" => true, "url" => url}) when is_binary(url), do: {:ok, url}

  defp normalize_response(%{"ok" => false, "error" => error} = body),
    do: {:error, {:slack_api_error, error, body}}

  defp normalize_response(%{"ok" => true} = body), do: {:error, {:missing_socket_url, body}}
  defp normalize_response(other), do: {:error, {:invalid_response, other}}

  defp api_url(opts) do
    base_url = Keyword.get(opts, :base_url, @base_url)
    String.trim_trailing(base_url, "/") <> "/apps.connections.open"
  end

  defp normalize_headers(nil), do: []

  defp normalize_headers(headers) when is_map(headers) do
    Enum.map(headers, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.map(headers, fn {key, value} -> {to_string(key), to_string(value)} end)
  end
end
