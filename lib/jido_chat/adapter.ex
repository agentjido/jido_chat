defmodule Jido.Chat.Adapter do
  @moduledoc """
  Stateless provider contract. An adapter maps one validated request Signal to
  one canonical result value. The Action wraps that value in a result Signal.

  `normalize/3` maps private provider input to an immutable Delivery of facts.
  The host owns webhook verification, acknowledgements, listeners, storage,
  retries, and publication. Client construction and capability reads perform no I/O.

  An adapter that declares `stream_text: :native` handles the StreamText request
  in `invoke/3`. Its source Enumerable is `opts[:stream]`. The adapter selects its
  delivery method and consumes the source in the Action execution task. Return the final
  canonical message, as for SendMessage. Do not put the source in a Signal.
  """
  alias Jido.Chat.{Client, Delivery}
  @type capabilities :: %{optional(atom()) => :native | :unsupported}
  @callback channel_type() :: atom()
  @callback capabilities() :: capabilities()
  @callback default_transport() :: module()
  @callback invoke(Client.t(), Jido.Signal.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback normalize(Client.t(), term(), keyword()) :: {:ok, Delivery.t()} | {:error, term()}
  @callback operations() :: [{module(), module()}]
  @callback event_definitions() :: [module()]
  @optional_callbacks default_transport: 0, operations: 0, event_definitions: 0

  @doc "Declares a stateless provider adapter."
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      @behaviour Jido.Chat.Adapter
      @impl true
      def channel_type, do: __MODULE__ |> Module.split() |> Enum.at(-2) |> Macro.underscore() |> String.to_atom()
      defoverridable channel_type: 0
    end
  end

  @doc "Returns provider extension request/Action pairs; core operations are separate."
  @spec operations(module()) :: [{module(), module()}]
  def operations(adapter) do
    if function_exported?(adapter, :operations, 0), do: adapter.operations(), else: []
  end

  @doc "Returns admitted incoming facts; older adapters admit the core fact set."
  @spec event_definitions(module()) :: [module()]
  def event_definitions(adapter) do
    if function_exported?(adapter, :event_definitions, 0),
      do: adapter.event_definitions(),
      else: Jido.Chat.event_definitions()
  end

  @doc "Returns explicit operation support. No fallback is inferred."
  @spec capabilities(module()) :: capabilities()
  def capabilities(adapter) do
    case validate_capabilities(adapter) do
      :ok ->
        declared = adapter.capabilities()

        operations =
          Map.new(Jido.Chat.Operations.Definitions.all(), fn {_, {_, operation, _, _, _}} ->
            {operation, Map.get(declared, operation, :unsupported)}
          end)

        Map.merge(declared, operations)

      {:error, error} ->
        raise error
    end
  end

  @doc "Validates explicit operation statuses without calling a provider."
  @spec validate_capabilities(module()) :: :ok | {:error, Jido.Chat.Errors.Contract.t()}
  def validate_capabilities(adapter) do
    true = Code.ensure_loaded?(adapter)
    declared = adapter.capabilities()

    valid =
      is_map(declared) and
        Enum.all?(declared, fn {key, status} -> is_atom(key) and status in [:native, :unsupported] end) and
        valid_extensions?(adapter)

    if valid, do: :ok, else: Jido.Chat.Signal.Policy.error(:invalid_capabilities)
  rescue
    _ -> Jido.Chat.Signal.Policy.error(:invalid_capabilities)
  end

  defp valid_extensions?(adapter) do
    extensions = operations(adapter)
    events = event_definitions(adapter)
    pairs = Jido.Chat.operations() ++ extensions

    types =
      Enum.map(pairs, fn {definition, action} ->
        true = Code.ensure_loaded?(action)
        true = action.signal_definition() == definition
        definition.type()
      end)

    definitions =
      (Jido.Chat.signal_definitions() ++
         Enum.flat_map(extensions, fn {_, action} -> action.signal_definitions() end) ++ events)
      |> Enum.uniq()

    _catalog = Jido.Signal.Catalog.new!(definitions)

    length(types) == length(Enum.uniq(types)) and Enum.all?(events, &fact_definition?/1)
  end

  defp fact_definition?(definition) do
    if Jido.Signal.defined?(definition) do
      case definition.schema() do
        %{fields: fields} when is_map(fields) or is_list(fields) ->
          fields = Map.new(fields)
          Enum.all?(["item_id", "delivery_id"], &match?(%{meta: %{required: true}}, fields[&1]))

        _ ->
          false
      end
    else
      false
    end
  end

  @doc "Renders a Markdown value."
  @spec render_markdown(term(), keyword()) :: String.t()
  def render_markdown(value, _opts \\ []), do: value |> Jido.Chat.Markdown.new() |> Jido.Chat.Markdown.stringify()
  @doc "Renders a card value."
  @spec render_card(term(), keyword()) :: map()
  def render_card(value, _opts \\ []), do: value |> Jido.Chat.Card.normalize() |> Jido.Chat.Card.to_adapter_payload()
  @doc "Renders a modal value."
  @spec render_modal(term(), keyword()) :: map()
  def render_modal(value, _opts \\ []), do: value |> Jido.Chat.Modal.new() |> Jido.Chat.Modal.to_adapter_payload()
  @doc "Renders a finite stream value."
  @spec render_stream(Enumerable.t()) :: String.t() | nil
  def render_stream(value), do: Jido.Chat.Markdown.StreamRenderer.render(value)
end
