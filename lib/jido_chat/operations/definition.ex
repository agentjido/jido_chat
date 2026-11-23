defmodule Jido.Chat.Operations.Definition do
  @moduledoc """
  Registers a native Action and its request, completion, and failure Signals.

  Use the request and completion schemas in the Action declaration. Call
  `run/3` from the Action to validate and execute the request through the
  configured adapter. The SDK and Plugin use the same operation definition
  for discovery, routing, and result Signals.
  """

  alias Jido.Chat.Operations.Execution
  alias Jido.Chat.Signal.{Policy, Schemas}

  @enforce_keys [:request, :action, :completed, :failed, :result_schema]
  defstruct @enforce_keys ++ [:capability]

  @type t :: %__MODULE__{
          request: module(),
          action: module(),
          completed: module(),
          failed: module(),
          capability: atom() | nil,
          result_schema: Jido.Joi.schema()
        }

  @doc "Executes one validated operation through the configured adapter."
  @spec run(t(), map(), map()) :: Jido.Action.result()
  def run(operation, params, context), do: run(operation, params, context, &invoke_adapter/3)

  @doc false
  def run(operation, params, context, invoke), do: Execution.run(operation, params, context, invoke)

  @doc false
  def invoke_adapter(client, request, opts), do: client.adapter.invoke(client, request, opts)

  @doc "Builds a completion Signal for the matching request."
  @spec reply(t(), Jido.Signal.t(), map(), keyword() | map()) :: {:ok, Jido.Signal.t()} | {:error, term()}
  def reply(operation, request, data, opts \\ [])

  def reply(%__MODULE__{request: definition, completed: completed}, %Jido.Signal{data: params} = request, data, opts)
      when is_map(params) and is_map(data) do
    if request.type == definition.type() and request.dataschema == definition.dataschema() and
         data["operation"] == request.type and matching_request?(definition, params, data) do
      Policy.reply(completed, data, request, opts)
    else
      Policy.error(:context_mismatch)
    end
  end

  def reply(_, _, _, _), do: Policy.error(:invalid_request)

  defp matching_request?(definition, params, data) do
    same_ids?(params, data) or
      case definition.validate_data(params) do
        {:ok, normalized} when is_map(normalized) -> same_ids?(normalized, data)
        _ -> false
      end
  end

  defp same_ids?(params, data),
    do: data["client_id"] == params["client_id"] and data["request_id"] == params["request_id"]

  @doc "Returns the request, completion, and failure Signal definitions."
  @spec signal_definitions(t()) :: [module()]
  def signal_definitions(%__MODULE__{request: request, completed: completed, failed: failed}),
    do: [request, completed, failed]

  @doc false
  def pair(%__MODULE__{request: request, action: action}), do: {request, action}

  @doc "Returns the native Signal options for a standard operation completion."
  @spec completion_options(module(), Jido.Joi.schema()) :: keyword()
  def completion_options(request, result_schema),
    do: completion_options(request.type(), request.dataschema(), result_schema)

  @doc false
  def completion_options(type, dataschema, result_schema),
    do: result_options(type, dataschema, "completed", Schemas.completion(type, result_schema))

  @doc "Returns the native Signal options for a standard operation failure."
  @spec failure_options(module()) :: keyword()
  def failure_options(request), do: failure_options(request.type(), request.dataschema())

  @doc false
  def failure_options(type, dataschema) do
    schema =
      Schemas.object(%{
        "client_id" => Schemas.id(),
        "request_id" => Schemas.id(),
        "operation" => Jido.Joi.literal(type),
        "code" =>
          Jido.Joi.enum([
            "unsupported",
            "provider_failure",
            "invalid_provider_result",
            "unauthorized",
            "forbidden",
            "not_found",
            "rate_limited",
            "timeout"
          ]),
        "retry_after_ms" => Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.optional(),
        "outcome" => Jido.Joi.enum(["not_attempted", "rejected", "unknown"])
      })

    result_options(type, dataschema, "failed", schema)
  end

  defp result_options(type, dataschema, suffix, schema) do
    opts = [type: type <> "." <> suffix, default_source: "urn:jido:chat:producer:local", schema: schema]
    if dataschema, do: Keyword.put(opts, :dataschema, dataschema <> ":" <> suffix), else: opts
  end

  @doc false
  def define_signal(module, options, env) do
    Module.create(
      module,
      quote do
        @moduledoc "Typed result Signal for a Chat operation."
        use Jido.Signal, unquote(Macro.escape(options))
      end,
      Macro.Env.location(env)
    )
  end
end
