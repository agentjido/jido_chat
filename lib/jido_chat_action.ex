defmodule Jido.ChatAction do
  @moduledoc """
  Defines a chat SignalAction that calls an immutable Client.

  `input` and `output` are Signal definitions. The input schema validates request
  data and Action parameters. The output schema validates completion data. Use
  the normal `Jido.Exec.run/3` with data and `%{client: client}` as context.
  `reply/3` builds the completion Signal without dispatch.

  `Jido.Chat.execute/3` supplies the request Signal as context, runs the Action,
  and builds its reply. Agent routes use `Jido.Chat.Plugin.Execute` to keep
  provider execution after commit.

  Existing `signal:` declarations use their registered result schema. Provider
  extensions supply `result_schema:` and can override `invoke/3`. Results must
  contain safe string-key JSON data. Failures keep the typed Chat error contract.
  """

  @doc "Calls a provider once. Override this callback for a provider extension."
  @callback invoke(Jido.Chat.Client.t(), Jido.Signal.t(), keyword()) :: {:ok, map()} | {:error, term()}

  @doc "Defines a chat Action on top of Jido.SignalAction."
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    action_opts =
      opts
      |> Keyword.drop([:signal, :result_schema, :input, :output])
      |> Keyword.put_new(:description, "Executes one typed chat request through an immutable client")
      |> Keyword.put_new(:vsn, 1)

    quote do
      @chat_contract Jido.ChatAction.Execution.contract(__MODULE__, unquote(opts), __ENV__)

      use Jido.SignalAction,
          unquote(action_opts) ++ [input: @chat_contract.input, output: @chat_contract.output]

      @behaviour Jido.ChatAction

      @doc "Returns the request Signal definition for this Action."
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
