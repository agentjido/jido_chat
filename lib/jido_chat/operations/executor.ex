defmodule Jido.Chat.Operations.Executor do
  @moduledoc false

  alias Jido.Chat.{Binding, RequestStore, Resources}
  alias Jido.Chat.Errors.Contract
  alias Jido.Chat.Operations.{Definitions, Failure, Invocation, Result}
  alias Jido.Chat.Signal.{Identity, OperationCompleted, OperationFailed, Policy}
  alias Jido.Signal.{Catalog, Trace}

  @resource_failures [:resource_expired, :resource_cancelled, :resource_failure]

  @doc false
  @spec execute(Binding.t(), Jido.Signal.t()) :: {:ok, Jido.Signal.t()} | {:error, Contract.t()}
  def execute(%Binding{} = binding, %Jido.Signal{} = request) do
    with :ok <- valid_binding(binding),
         {:ok, request} <- validate_request(request),
         definition when not is_nil(definition) <- Definitions.lookup(request.type),
         :ok <- request_context(binding, request),
         {:ok, claim} <- claim(binding, request, definition) do
      case claim do
        {:cached, result} ->
          result

        {:claimed, claim} ->
          result = run(binding, request, definition)

          case RequestStore.complete(binding, claim, result) do
            :ok -> result
            error -> error
          end
      end
    else
      {:error, %Contract{}} = error -> error
      _ -> Policy.error(:invalid_request)
    end
  end

  def execute(_binding, _request), do: Policy.error(:invalid_request)

  defp valid_binding(binding) do
    if binding.source == Identity.binding_source(binding.id) and Keyword.keyword?(binding.options) and
         :ets.info(binding.resources) != :undefined do
      :ok
    else
      Policy.error(:invalid_binding)
    end
  rescue
    _ -> Policy.error(:invalid_binding)
  end

  defp validate_request(request) do
    with {:ok, ^request} <- request |> Jido.Signal.to_map() |> Jido.Signal.from_map(),
         {:ok, request} <- Catalog.validate(Catalog.new!(Jido.Chat.signal_definitions()), request),
         {:ok, request} <- Policy.validate(request),
         true <- parent_id?(request.id) do
      {:ok, request}
    else
      {:error, %Contract{}} = error -> error
      _ -> Policy.error(:invalid_request)
    end
  end

  defp parent_id?(id), do: byte_size(id) in 1..128

  defp request_context(binding, request) do
    room = request.data["room_id"]
    expected = if is_binary(room), do: Identity.conversation_subject(binding.id, room)
    if is_nil(request.subject) or request.subject == expected, do: :ok, else: Policy.error(:context_mismatch)
  rescue
    _ -> Policy.error(:invalid_context)
  end

  defp claim(binding, request, {_module, operation, _fields, _shape, _schema}) do
    key = {:request, request.data["request_id"]}
    digest = :crypto.hash(:sha256, :erlang.term_to_binary({operation, request.data}, [:deterministic]))

    RequestStore.claim(binding, key, digest)
  end

  defp run(binding, request, definition) do
    try do
      case Invocation.run(binding, request, definition) do
        {:error, %Contract{code: code}} when code in @resource_failures ->
          failure(binding, request, definition, code)

        {:error, %Contract{}} = error ->
          error

        {:error, :unsupported} ->
          failure(binding, request, definition, :unsupported, :degraded)

        {:error, :invalid_provider_result} ->
          failure(binding, request, definition, :invalid_provider_result)

        {:error, reason} ->
          failure(binding, request, definition, :provider_failure, Failure.classify(reason), Failure.tag(reason))

        :ok ->
          completed(binding, request, definition, :ok)

        {:ok, value} ->
          completed(binding, request, definition, value)

        _ ->
          failure(binding, request, definition, :invalid_provider_result)
      end
    rescue
      _ -> failure(binding, request, definition, :provider_failure, :recoverable)
    catch
      _, _ -> failure(binding, request, definition, :provider_failure, :recoverable)
    end
  end

  defp completed(binding, request, {_module, operation, _fields, :resource, _schema} = definition, value) do
    if is_binary(value) do
      with {:ok, ref} <- Resources.put(binding, "media", value, []) do
        success(binding, request, operation, %{"resource_ref" => ref})
      end
    else
      failure(binding, request, definition, :invalid_provider_result)
    end
  end

  defp completed(binding, request, {_module, operation, _fields, shape, schema} = definition, value) do
    with {:ok, selected} <- Result.project(shape, value, request.data),
         {:ok, selected} <- Zoi.parse(schema, selected),
         :ok <- Policy.validate_json(selected, []) do
      if byte_size(Jason.encode!(selected)) > 262_144 do
        large_result(binding, request, operation, selected)
      else
        case success(binding, request, operation, selected) do
          {:error, %Contract{code: :signal_too_large}} -> large_result(binding, request, operation, selected)
          other -> other
        end
      end
    else
      _ -> failure(binding, request, definition, :invalid_provider_result)
    end
  end

  defp large_result(binding, request, operation, selected) do
    with {:ok, ref} <- Resources.put(binding, "result", selected, []) do
      success(binding, request, operation, %{"resource_ref" => ref})
    end
  end

  defp success(binding, request, operation, result) do
    OperationCompleted.new(
      %{"operation" => Atom.to_string(operation), "request_id" => request.data["request_id"], "result" => result},
      result_options(binding, request, operation, result)
    )
  end

  defp failure(binding, request, {_module, operation, _fields, _shape, _schema}, code, class \\ :fatal, tag \\ nil) do
    result =
      OperationFailed.new(
        %{
          "operation" => Atom.to_string(operation),
          "request_id" => request.data["request_id"],
          "code" => Atom.to_string(code),
          "retryable" => class == :recoverable
        },
        result_options(binding, request, operation, nil)
      )

    case result do
      {:ok, signal} -> Failure.remember(binding, signal, class, tag)
      _ -> :ok
    end

    result
  end

  defp result_options(binding, request, operation, result) do
    room = request.data["room_id"] || if(operation == :open_dm and is_map(result), do: result["id"])
    subject = if is_binary(room), do: Identity.conversation_subject(binding.id, room)
    trace = Trace.child(Trace.get(request) || Trace.new())
    extensions = %{"causationid" => request.id, "traceparent" => Trace.to_traceparent(trace)}
    extensions = if trace.tracestate, do: Map.put(extensions, "tracestate", trace.tracestate), else: extensions
    [source: binding.source, subject: subject, extensions: extensions]
  end
end
