defmodule Jido.Chat.Operations.Execution do
  @moduledoc false
  alias Jido.Chat.Operations.Definition, as: Operation
  alias Jido.Chat.Signal.{Identity, Policy}
  alias Jido.Signal.Catalog

  @doc false
  def invoke_stream(client, signal, opts) do
    with {:ok, chunks} <- Keyword.fetch(opts, :stream),
         true <- not is_nil(Enumerable.impl_for(chunks)) do
      client.adapter.invoke(client, signal, opts)
    else
      _ -> {:error, {:not_attempted, :invalid_stream}}
    end
  end

  defp checked_signal(%Jido.Signal{} = signal, definition, catalog) do
    with true <- signal.type == definition.type() and signal.dataschema == definition.dataschema(),
         {:ok, signal} <- Policy.validate(catalog, signal) do
      {:ok, signal}
    else
      {:error, _} = error -> error
      _ -> Policy.error(:invalid_request)
    end
  end

  defp checked_signal(_, _, _), do: Policy.error(:invalid_request)

  @doc false
  def run(operation, params, %{client: %Jido.Chat.Client{} = client} = context, call_provider) do
    opts = Map.get(context, :options, [])

    with {:ok, request} <- request(operation.request, params, client, context),
         {:ok, request} <- checked_signal(request, operation.request, Catalog.new!([operation.request])),
         :ok <- match_data(request, params),
         {:ok, request} <- Jido.Chat.Signal.Policy.prepare(request),
         :ok <- validate_context(client, request),
         true <- is_list(opts) and Keyword.keyword?(opts) do
      if is_nil(operation.capability) or client.adapter.capabilities()[operation.capability] == :native do
        Jido.Trace.Context.with_context(Jido.Signal.Context.get_trace(request), fn ->
          invoke(operation, client, request, opts, call_provider)
        end)
      else
        failure(operation, client, request, :unsupported, "not_attempted")
      end
    else
      {:error, _} = error -> error
      _ -> Policy.error(:invalid_options)
    end
  end

  def run(_, _, _, _), do: Policy.error(:invalid_client)

  defp request(definition, params, client, context) do
    case Map.fetch(context, :signal) do
      {:ok, signal} -> {:ok, signal}
      :error -> definition.new(params, source: client.source)
    end
  end

  defp match_data(%Jido.Signal{data: data}, data), do: :ok
  defp match_data(_request, _data), do: Policy.error(:context_mismatch)

  defp validate_context(client, request) do
    data = request.data

    valid =
      is_map(data) and is_binary(data["request_id"]) and data["request_id"] != "" and
        data["client_id"] == client.id and
        (not Map.has_key?(data, "room_id") or (is_binary(data["room_id"]) and data["room_id"] != ""))

    if valid and request.subject in [nil, subject(client, request)] and references_match?(data, client.id),
      do: :ok,
      else: Policy.error(:context_mismatch)
  end

  defp references_match?(value, client_id) when is_map(value) do
    matches =
      case value do
        %{"client_id" => ref_client, "id" => _, "kind" => kind} when kind in ["file", "media", "url"] ->
          ref_client == client_id

        _ ->
          true
      end

    matches and Enum.all?(value, fn {_, item} -> references_match?(item, client_id) end)
  end

  defp references_match?(value, client_id) when is_list(value),
    do: Enum.all?(value, &references_match?(&1, client_id))

  defp references_match?(_, _), do: true

  defp invoke(operation, client, request, opts, call_provider) do
    case provider_call(call_provider, client, request, opts) do
      {:ok, value} ->
        complete(operation, client, request, value)

      {:error, :invalid_provider_result} ->
        failure(operation, client, request, :invalid_provider_result, "unknown")

      {:error, {:unknown, code, hints}} when is_map(hints) ->
        failure(operation, client, request, safe_code(code), "unknown", hints)

      {:error, {:rejected, code, hints}} when is_map(hints) ->
        failure(operation, client, request, safe_code(code), "rejected", hints)

      {:error, {:rejected, code}} ->
        failure(operation, client, request, safe_code(code), "rejected")

      {:error, {:not_attempted, :unsupported}} ->
        failure(operation, client, request, :unsupported, "not_attempted")

      {:error, {:not_attempted, _}} ->
        failure(operation, client, request, :provider_failure, "not_attempted")

      _ ->
        failure(operation, client, request, :provider_failure, "unknown")
    end
  end

  defp complete(operation, client, request, value) do
    with {:ok, result} when is_map(result) <- Jido.Joi.parse(operation.result_schema, value),
         :ok <- Policy.validate_json(result, []),
         true <- references_match?(result, client.id),
         true <-
           is_nil(request.data["room_id"]) or is_nil(result["room_id"]) or
             request.data["room_id"] == result["room_id"],
         data = result_data(operation, client, request) |> Map.put("result", result) do
      {:ok, data}
    else
      _ -> failure(operation, client, request, :invalid_provider_result, "unknown")
    end
  end

  defp provider_call(call_provider, client, request, opts) do
    call_provider.(client, request, opts)
  rescue
    _ -> {:error, :provider_failure}
  catch
    _, _ -> {:error, :provider_failure}
  end

  defp safe_code(code)
       when code in [
              :unsupported,
              :invalid_provider_result,
              :unauthorized,
              :forbidden,
              :not_found,
              :rate_limited,
              :timeout
            ],
       do: code

  defp safe_code(_), do: :provider_failure

  @doc false
  def reply(operation, client, request, data) do
    case Operation.reply(operation, request, data, result_options(client, request)) do
      {:ok, _} = reply -> reply
      {:error, _} -> failure(operation, client, request, :invalid_provider_result, "unknown")
    end
  end

  @doc false
  def failure(operation, client, request, code, outcome, hints \\ %{}) do
    data = result_data(operation, client, request) |> Map.merge(%{"code" => Atom.to_string(code), "outcome" => outcome})

    data =
      case hints[:retry_after_ms] do
        value when is_integer(value) and value >= 0 -> Map.put(data, "retry_after_ms", value)
        _ -> data
      end

    with {:ok, signal} <-
           Jido.Chat.Signal.Policy.reply(operation.failed, data, request, result_options(client, request)) do
      {:error, Jido.Chat.Error.exception(code: code, signal: signal)}
    end
  end

  defp result_data(operation, client, request),
    do: %{"client_id" => client.id, "request_id" => request.data["request_id"], "operation" => operation.request.type()}

  defp subject(client, request) do
    if request.data["room_id"], do: Identity.conversation_subject(client.id, request.data["room_id"])
  end

  defp result_options(client, request) do
    [source: client.source, subject: subject(client, request)]
  end
end
