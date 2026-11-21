defmodule Jido.Chat.Signal.Transport.JsonRpcClient do
  @moduledoc "HTTP JSON-RPC transport for `signal-cli daemon --http`."
  @behaviour Jido.Chat.Signal.Transport

  @compile {:no_warn_undefined, Req}

  alias Jido.Chat.Providers.Dependencies
  alias Jido.Chat.Signal.AttachmentRef

  @impl true
  def send_message(account, target, text, opts) do
    with {:ok, params} <-
           target
           |> send_params(text)
           |> maybe_put_attachments(opts) do
      params
      |> maybe_put_quote(target, opts)
      |> maybe_put_account(account)
      |> then(&rpc("send", &1, opts))
    end
  end

  @impl true
  def receive_messages(account, opts \\ []) do
    params =
      %{}
      |> maybe_put_account(account)
      |> maybe_put_receive_timeout(opts)
      |> maybe_put_max_messages(opts)

    with {:ok, result} <- rpc("receive", params, opts) do
      {:ok, normalize_receive_messages(result)}
    end
  end

  defp rpc(method, params, opts) do
    with :ok <- Dependencies.req() do
      request(method, params, opts)
    end
  end

  defp request(method, params, opts) do
    endpoint =
      Keyword.get(opts, :endpoint) || System.get_env("SIGNAL_RPC_ENDPOINT") ||
        "http://127.0.0.1:8080/api/v1/rpc"

    id = System.unique_integer([:positive]) |> to_string()
    body = %{"jsonrpc" => "2.0", "method" => method, "params" => params, "id" => id}
    request_opts = request_opts(endpoint, body, method, params, opts)

    case Req.post(request_opts) do
      {:ok, %{status: status, body: %{"result" => result}}} when status in 200..299 ->
        {:ok, result}

      {:ok, %{status: status, body: %{"error" => error}}} ->
        {:error, {:signal_rpc_error, status, error}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:signal_rpc_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_opts(endpoint, body, method, params, opts) do
    opts
    |> Keyword.get(:req_options, [])
    |> Keyword.merge(url: endpoint, json: body)
    |> maybe_put_req_receive_timeout(method, params, opts)
  end

  defp maybe_put_req_receive_timeout(req_opts, "receive", params, opts) do
    timeout_s = Map.get(params, "timeout")

    timeout_ms =
      case opts |> Keyword.get(:http_receive_timeout_ms) |> normalize_integer() do
        nil when is_number(timeout_s) -> max(trunc(timeout_s * 1_000) + 5_000, 15_000)
        nil -> nil
        value -> value
      end

    case timeout_ms do
      nil -> req_opts
      value -> Keyword.put_new(req_opts, :receive_timeout, value)
    end
  end

  defp maybe_put_req_receive_timeout(req_opts, _method, _params, _opts), do: req_opts

  defp maybe_put_account(params, account) do
    if account in [nil, ""], do: params, else: Map.put(params, "account", account)
  end

  defp maybe_put_receive_timeout(params, opts) do
    case Keyword.get(opts, :receive_timeout_s, Keyword.get(opts, :timeout_s)) do
      nil -> params
      timeout -> Map.put(params, "timeout", normalize_number(timeout))
    end
  end

  defp maybe_put_max_messages(params, opts) do
    case Keyword.get(opts, :max_messages) do
      nil -> params
      max_messages -> Map.put(params, "maxMessages", normalize_integer(max_messages))
    end
  end

  defp maybe_put_attachments(params, opts) do
    case Keyword.get(opts, :attachments, []) do
      [] ->
        {:ok, params}

      attachments ->
        with {:ok, refs} <- AttachmentRef.refs(attachments) do
          {:ok, Map.put(params, "attachments", refs)}
        end
    end
  end

  defp maybe_put_quote(params, target, opts) do
    timestamp = Keyword.get(opts, :quote_timestamp) || Keyword.get(opts, :reply_to_id)

    author =
      Keyword.get(opts, :quote_author) || Keyword.get(opts, :reply_author) || to_string(target)

    message = Keyword.get(opts, :quote_message)

    cond do
      timestamp in [nil, ""] ->
        params

      message in [nil, ""] ->
        params
        |> Map.put("quoteTimestamp", timestamp)
        |> Map.put("quoteAuthor", author)

      true ->
        params
        |> Map.put("quoteTimestamp", timestamp)
        |> Map.put("quoteAuthor", author)
        |> Map.put("quoteMessage", message)
    end
  end

  defp send_params(target, text) do
    target = to_string(target)

    if String.starts_with?(target, "group:") do
      %{"groupId" => String.replace_prefix(target, "group:", ""), "message" => text}
    else
      %{"recipient" => [target], "message" => text}
    end
  end

  defp normalize_receive_messages(messages) when is_list(messages), do: messages
  defp normalize_receive_messages(nil), do: []
  defp normalize_receive_messages(message), do: [message]

  defp normalize_number(value) when is_number(value), do: value

  defp normalize_number(value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, ""} -> parsed
      _ -> value
    end
  end

  defp normalize_number(value), do: value

  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> value
    end
  end

  defp normalize_integer(value), do: value
end
