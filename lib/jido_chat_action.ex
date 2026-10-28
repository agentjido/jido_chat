defmodule Jido.ChatAction do
  use Boundary,
    top_level?: true,
    check: [in: false, out: false]

  @moduledoc """
  Defines a chat Action with typed request and result Signals.

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

  @doc "Defines a chat Action with a Signal contract."
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    action_opts =
      opts
      |> Keyword.drop([:signal, :result_schema, :input, :output])
      |> Keyword.put_new(:description, "Executes one typed chat request through an immutable client")
      |> Keyword.put_new(:vsn, 1)

    quote do
      @chat_contract Jido.ChatAction.Execution.contract(__MODULE__, unquote(opts), __ENV__)

      use Jido.Action,
          unquote(action_opts) ++
            [
              schema: @chat_contract.input[:schema],
              output_schema: @chat_contract.output[:schema]
            ]

      @behaviour Jido.ChatAction

      @doc "Returns the chat contract version."
      @spec vsn() :: pos_integer()
      def vsn, do: @chat_contract.vsn

      @doc false
      @spec __signal_action__() :: map()
      def __signal_action__ do
        %{
          vsn: @chat_contract.vsn,
          input: Map.new(@chat_contract.input),
          output: Map.new(@chat_contract.output)
        }
      end

      @doc false
      @spec __signal_definition__() :: map()
      def __signal_definition__, do: Map.new(@chat_contract.input)

      @doc "Returns the request Signal type."
      @spec type() :: String.t()
      def type, do: @chat_contract.input[:type]

      @doc "Returns the default request Signal source."
      @spec default_source() :: String.t() | nil
      def default_source, do: @chat_contract.input[:default_source]

      @doc "Returns the request Signal content type."
      @spec datacontenttype() :: String.t() | nil
      def datacontenttype, do: @chat_contract.input[:datacontenttype]

      @doc "Returns the request Signal schema URI."
      @spec dataschema() :: String.t() | nil
      def dataschema, do: @chat_contract.input[:dataschema]

      @doc "Validates request Signal data."
      @spec validate_data(term()) :: Zoi.result()
      def validate_data(data), do: Zoi.parse(schema(), data)

      @doc "Builds a validated request Signal."
      @spec new(term(), keyword() | map()) ::
              {:ok, Jido.Signal.t()} | {:error, [Zoi.Error.t()] | String.t()}
      def new(data \\ %{}, opts \\ []),
        do: Jido.ChatAction.Execution.new(__MODULE__, data, opts)

      @doc "Builds a validated request Signal or raises."
      @spec new!(term(), keyword() | map()) :: Jido.Signal.t() | no_return()
      def new!(data \\ %{}, opts \\ []) do
        case new(data, opts) do
          {:ok, signal} -> signal
          {:error, errors} when is_list(errors) -> raise Zoi.ParseError, errors: errors
          {:error, reason} -> raise ArgumentError, "invalid signal: #{inspect(reason)}"
        end
      end

      @doc "Builds a correlated completion Signal."
      @spec reply(Jido.Signal.t(), map(), keyword() | map()) ::
              {:ok, Jido.Signal.t()} | {:error, term()}
      def reply(request, data, opts \\ []),
        do: Jido.ChatAction.Execution.reply(@chat_contract, request, data, opts)

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
