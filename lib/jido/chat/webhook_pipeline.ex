defmodule Jido.Chat.WebhookPipeline do
  @moduledoc false

  alias Jido.Chat.{Adapter, EventEnvelope, WebhookRequest, WebhookResponse}

  @type resolve_adapter_fun :: (map(), atom() -> {:ok, module()} | {:error, term()})
  @type process_event_fun ::
          (map(), atom(), EventEnvelope.t() | map(), keyword() ->
             {:ok, map(), EventEnvelope.t()} | {:error, term()})

  @spec handle_request(
          map(),
          atom(),
          WebhookRequest.t() | map(),
          keyword(),
          resolve_adapter_fun(),
          process_event_fun()
        ) ::
          {:ok, map(), EventEnvelope.t() | nil, WebhookResponse.t()}
  def handle_request(
        chat,
        adapter_name,
        request_or_payload,
        opts,
        resolve_adapter,
        process_event
      )
      when is_map(chat) and is_atom(adapter_name) and is_list(opts) and
             is_function(resolve_adapter, 2) and is_function(process_event, 4) do
    try do
      case resolve_adapter.(chat, adapter_name) do
        {:ok, adapter_module} ->
          request = normalize_webhook_request(adapter_name, request_or_payload, opts)
          request_opts = Keyword.put(opts, :request, request)

          case Adapter.verify_webhook(adapter_module, request, request_opts) do
            :ok ->
              handle_verified_webhook(
                chat,
                adapter_name,
                adapter_module,
                request,
                request_opts,
                process_event
              )

            {:error, reason} ->
              webhook_error_result(adapter_module, chat, nil, reason, request_opts)
          end

        {:error, {:unknown_adapter, unknown_adapter}} ->
          {:ok, chat, nil,
           WebhookResponse.error(404, %{
             error: "unknown_adapter",
             adapter_name: to_string(unknown_adapter)
           })}

        {:error, reason} ->
          {:ok, chat, nil, fallback_webhook_response(reason)}
      end
    rescue
      exception ->
        {:ok, chat, nil, fallback_webhook_response({:exception, exception})}
    end
  end

  defp handle_verified_webhook(
         chat,
         adapter_name,
         adapter_module,
         %WebhookRequest{} = request,
         request_opts,
         process_event
       ) do
    case Adapter.parse_event(adapter_module, request, request_opts) do
      {:ok, :noop} ->
        case Adapter.format_webhook_response(adapter_module, {:ok, chat, :noop}, request_opts) do
          {:ok, response} ->
            {:ok, chat, nil, response}

          {:error, reason} ->
            webhook_error_result(
              adapter_module,
              chat,
              nil,
              {:webhook_response_format_error, reason},
              request_opts
            )
        end

      {:ok, envelope} ->
        case process_event.(chat, adapter_name, envelope, request_opts) do
          {:ok, routed_chat, routed_envelope} ->
            case Adapter.format_webhook_response(
                   adapter_module,
                   {:ok, routed_chat, routed_envelope},
                   request_opts
                 ) do
              {:ok, response} ->
                {:ok, routed_chat, routed_envelope, response}

              {:error, reason} ->
                webhook_error_result(
                  adapter_module,
                  routed_chat,
                  routed_envelope,
                  {:webhook_response_format_error, reason},
                  request_opts
                )
            end

          {:error, reason} ->
            webhook_error_result(adapter_module, chat, envelope, reason, request_opts)
        end

      {:error, reason} ->
        webhook_error_result(adapter_module, chat, nil, reason, request_opts)
    end
  end

  defp webhook_error_result(adapter_module, chat, envelope, reason, opts) do
    case Adapter.format_webhook_response(adapter_module, {:error, reason}, opts) do
      {:ok, response} ->
        {:ok, chat, envelope, response}

      {:error, _format_error} ->
        {:ok, chat, envelope, fallback_webhook_response(reason)}
    end
  end

  defp fallback_webhook_response(:invalid_webhook_secret),
    do: WebhookResponse.error(401, %{error: "invalid_webhook_secret"})

  defp fallback_webhook_response(:invalid_signature),
    do: WebhookResponse.error(401, %{error: "invalid_signature"})

  defp fallback_webhook_response({:unknown_adapter, adapter_name}),
    do:
      WebhookResponse.error(404, %{
        error: "unknown_adapter",
        adapter_name: to_string(adapter_name)
      })

  defp fallback_webhook_response({:webhook_response_format_error, _reason}),
    do: WebhookResponse.error(500, %{error: "webhook_response_format_error"})

  defp fallback_webhook_response({:exception, exception}),
    do: WebhookResponse.error(500, %{error: "webhook_exception", reason: inspect(exception)})

  defp fallback_webhook_response(reason),
    do: WebhookResponse.error(400, %{error: "invalid_webhook_request", reason: inspect(reason)})

  defp normalize_webhook_request(adapter_name, %WebhookRequest{} = request, _opts) do
    %{request | adapter_name: request.adapter_name || adapter_name}
  end

  defp normalize_webhook_request(adapter_name, payload, opts) when is_map(payload) do
    payload_map = payload[:payload] || payload["payload"] || payload

    headers =
      opts[:headers] || payload[:headers] || payload["headers"] || %{}

    WebhookRequest.new(%{
      adapter_name: adapter_name,
      method: payload[:method] || payload["method"] || opts[:method] || "POST",
      path: payload[:path] || payload["path"] || opts[:path],
      headers: headers,
      payload: payload_map,
      query: payload[:query] || payload["query"] || opts[:query] || %{},
      raw: payload,
      metadata: payload[:metadata] || payload["metadata"] || %{}
    })
  end
end
