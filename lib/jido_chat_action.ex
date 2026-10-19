defmodule Jido.ChatAction do
  @moduledoc """
  Builds a native Jido Action for one typed chat request Signal.

      use Jido.ChatAction,
        name: "chat_send_message",
        signal: Jido.Chat.Signal.SendMessage

  Core requests use their declared result schemas and capability checks. A provider
  extension supplies `:result_schema` and can override `invoke/3`. The result must
  be a canonical string-key map. The shared boundary validates the request, client,
  references, and result. It creates safe result Signals and retains trace context.

  All Actions get nested `Completed` and `Failed` Signal definitions. Their types
  append `.completed` and `.failed` to the request type. Their schema URNs append
  `:completed` and `:failed` to the request schema URN. No registry edit is needed.
  Use `signal_definitions/0` to add all three definitions to a native Signal catalog.

  Request data must include `client_id` and `request_id`. Use `room_id` for a room
  operation. Context is `%{client: client, options: private_options}`. Input and
  successful output are `%{signal: signal}`. Serialized agent input can use
  `%{"signal" => envelope}`. The Action decodes it with its exact definition.
  `to_json/0` exposes the full wire envelope and typed data schemas. Provider failures return a
  `Jido.Chat.Error` with a failure Signal. This module starts no process.
  """

  @doc "Calls a provider once. Override this callback for a provider extension."
  @callback invoke(Jido.Chat.Client.t(), Jido.Signal.t(), keyword()) :: {:ok, map()} | {:error, term()}

  @doc "Defines the schemas, validation, and execution boundary for a native chat Action."
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    signal = Keyword.fetch!(opts, :signal)
    result_schema = Keyword.get(opts, :result_schema)

    action_opts =
      opts
      |> Keyword.drop([:signal, :result_schema])
      |> Keyword.put_new(:description, "Executes one typed chat request through an immutable client")

    quote do
      @chat_contract Jido.ChatAction.Execution.contract(__MODULE__, unquote(signal), unquote(result_schema), __ENV__)

      use Jido.Action,
          unquote(action_opts) ++
            [
              schema: Jido.ChatAction.Execution.input_schema(@chat_contract.signal),
              output_schema: Jido.ChatAction.Execution.output_schema(@chat_contract)
            ]

      defoverridable to_json: 0

      @doc "Returns complete wire Signal schemas for agent and tool discovery."
      @spec to_json() :: map()
      def to_json do
        super()
        |> Map.put("input_schema", Jido.ChatAction.Execution.json_schema(@chat_contract.signal))
        |> Map.put("output_schema", Jido.ChatAction.Execution.json_schema(@chat_contract.completed))
      end

      @impl Jido.Action
      def on_before_validate_params(params),
        do: Jido.ChatAction.Execution.prepare_params(params, @chat_contract.signal)

      @behaviour Jido.ChatAction

      @doc "Returns the exact request Signal definition for this Action."
      @spec signal_definition() :: module()
      def signal_definition, do: @chat_contract.signal

      @doc "Returns the request, completion, and failure Signal definitions."
      @spec signal_definitions() :: [module()]
      def signal_definitions, do: [@chat_contract.signal, @chat_contract.completed, @chat_contract.failed]

      @doc "Returns the Zoi schema for the canonical provider result map."
      @spec result_schema() :: Zoi.schema()
      def result_schema, do: @chat_contract.result_schema

      @impl Jido.Action
      def run(params, context), do: Jido.ChatAction.Execution.run(__MODULE__, @chat_contract, params, context)

      @impl Jido.ChatAction
      @doc "Calls the configured adapter. Override this callback for a provider extension."
      def invoke(client, signal, opts), do: client.adapter.invoke(client, signal, opts)

      defoverridable invoke: 3
    end
  end
end
