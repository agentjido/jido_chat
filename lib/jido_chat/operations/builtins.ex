defmodule Jido.Chat.Operations.Builtins do
  @moduledoc false

  alias Jido.Chat.Operations.Definition, as: Operation

  # Generate the shipped native Actions from their operation tables. The
  # forwarding functions preserve the existing Action API.
  @doc false
  def define(action, request, result_schema, name, opts, env) do
    Code.ensure_compiled!(request)
    completed = Module.concat(action, Completed)
    failed = Module.concat(action, Failed)
    type = Macro.compile_apply(request, :type, [], env)
    dataschema = Macro.compile_apply(request, :dataschema, [], env)
    Operation.define_signal(completed, Operation.completion_options(type, dataschema, result_schema), env)
    Operation.define_signal(failed, Operation.failure_options(type, dataschema), env)

    operation = %Operation{
      action: action,
      request: request,
      completed: completed,
      failed: failed,
      result_schema: result_schema,
      capability: opts[:capability]
    }

    description = Keyword.get(opts, :description, "Executes one typed chat request through an immutable client")
    invoke = Keyword.get(opts, :invoke, {Operation, :invoke_adapter, []})

    defmodule action do
      @moduledoc Keyword.get(opts, :doc, description)
      @operation operation
      @request request
      @invoke invoke

      use Jido.Action,
        name: name,
        description: description,
        schema: request.schema(),
        output_schema: completed.schema()

      @doc false
      def __signal_definition__(), do: @request.__signal_definition__()
      @doc "Returns the request Signal type."
      def type(), do: @request.type()
      @doc "Returns the default request Signal source."
      def default_source(), do: @request.default_source()
      @doc "Returns the request Signal content type."
      def datacontenttype(), do: @request.datacontenttype()
      @doc "Returns the request Signal schema URI."
      def dataschema(), do: @request.dataschema()
      @doc "Validates request Signal data."
      def validate_data(data), do: @request.validate_data(data)
      @doc "Builds a request Signal."
      def new(data \\ %{}, opts \\ []), do: @request.new(data, opts)
      @doc "Builds a request Signal or raises."
      def new!(data \\ %{}, opts \\ []), do: @request.new!(data, opts)

      @doc "Returns the chat contract version."
      def vsn, do: 1

      @doc "Returns the request Signal definition."
      def signal_definition, do: @request

      @doc "Returns the request, completion, and failure Signal definitions."
      def signal_definitions, do: Operation.signal_definitions(@operation)

      @doc "Returns the schema for the canonical provider result."
      def result_schema, do: @operation.result_schema

      @doc "Builds a completion Signal for the matching request."
      def reply(request, data, opts \\ []), do: Operation.reply(@operation, request, data, opts)

      @doc "Calls the provider for this operation."
      def invoke(client, signal, opts) do
        {module, function, arguments} = @invoke
        apply(module, function, arguments ++ [client, signal, opts])
      end

      @impl Jido.Action
      def run(params, context), do: Operation.run(@operation, params, context, &__MODULE__.invoke/3)
    end

    operation
  end
end
