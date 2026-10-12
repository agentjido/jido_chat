defmodule Jido.Chat.Handlers do
  @moduledoc """
  Local typed fact handlers selected by the native Signal Router.

  Registration captures callbacks and observation targets once. Handlers receive
  the accepted Signal. Message subscriptions, mentions, and text policy stay in
  this application runner. Membership has a separate exact type route.

  A unary callback observes a Signal. A binary callback returns `{:ok, state}`.
  `handle/2` returns the updated local handler value plus the native observation
  result. Observation failure does not rerun accepted handlers. After callback
  failure, keep the returned claimed handler value. Its memory identity prevents
  the same fact from rerunning earlier callbacks.
  """

  alias Jido.Chat.{Binding, Delivery}
  alias Jido.Chat.Handlers.Families
  alias Jido.Chat.Signal.{Identity, Policy}
  alias Jido.Signal.{Catalog, Dispatch, Router}

  @schema Zoi.struct(__MODULE__, %{
            state: Zoi.any(),
            router: Zoi.any(),
            family_router: Zoi.any(),
            handlers: Zoi.map(),
            next_id: Zoi.integer(),
            subscriptions: Zoi.any(),
            seen: Zoi.any(),
            seen_order: Zoi.any(),
            dedupe_limit: Zoi.integer(),
            observers: Zoi.any()
          })
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Creates local application state and validated native Dispatch observers."
  @spec new(term(), keyword()) :: {:ok, t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def new(state \\ %{}, opts \\ []) do
    with {:ok, observers} <- Dispatch.validate_opts(Keyword.get(opts, :observers, [])),
         {:ok, router} <- Router.new([]),
         limit when is_integer(limit) and limit > 0 <- Keyword.get(opts, :dedupe_limit, 1_000) do
      {:ok,
       %__MODULE__{
         state: state,
         router: router,
         family_router: Families.router(),
         handlers: %{},
         next_id: 0,
         subscriptions: MapSet.new(),
         seen: MapSet.new(),
         seen_order: [],
         dedupe_limit: limit,
         observers: observers
       }}
    else
      _ -> Policy.error(:invalid_handler)
    end
  rescue
    _ -> Policy.error(:invalid_handler)
  end

  @doc "Registers an exact public fact definition and a local callback."
  @spec on(t(), module(), function(), keyword()) :: {:ok, t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def on(%__MODULE__{} = handlers, definition, callback, opts \\ []) do
    mode = Keyword.get(opts, :mode, :fact)
    pattern = Keyword.get(opts, :pattern)

    valid =
      definition in Jido.Chat.signal_definitions() and definition.__signal_kind__() == :fact and
        (is_function(callback, 1) or is_function(callback, 2)) and
        mode in [:fact, :message, :mention, :subscribed] and
        (is_nil(pattern) or is_struct(pattern, Regex)) and
        (mode == :fact or definition == Jido.Chat.Signal.MessageReceived)

    with true <- valid, {:ok, router} <- Router.add(handlers.router, {definition, handlers.next_id}) do
      entry = %{callback: callback, mode: mode, pattern: pattern}

      {:ok,
       %{
         handlers
         | router: router,
           handlers: Map.put(handlers.handlers, handlers.next_id, entry),
           next_id: handlers.next_id + 1
       }}
    else
      _ -> Policy.error(:invalid_handler)
    end
  rescue
    _ -> Policy.error(:invalid_handler)
  end

  @doc "Subscribes message handlers to a binding-scoped primary conversation."
  @spec subscribe(t(), Binding.t(), String.t()) :: t()
  def subscribe(%__MODULE__{} = handlers, binding, room) do
    key = {binding.source, Identity.conversation_subject(binding.id, room)}
    %{handlers | subscriptions: MapSet.put(handlers.subscriptions, key)}
  end

  @doc "Validates a complete delivery before applying its ordered facts."
  @spec accept(t(), Binding.t(), Delivery.t()) ::
          {:ok, t(), list()} | {:error, Jido.Chat.Errors.Contract.t()} | {:error, Jido.Chat.Errors.Contract.t(), t()}
  def accept(handlers, binding, delivery) do
    with {:ok, delivery} <- Delivery.validate(binding, delivery) do
      Enum.reduce_while(delivery.signals, {:ok, handlers, []}, fn signal, {:ok, state, observations} ->
        case handle(state, signal) do
          {:ok, state, observation} -> {:cont, {:ok, state, observations ++ [observation]}}
          {:error, error, state} -> {:halt, {:error, error, state}}
          error -> {:halt, error}
        end
      end)
    end
  end

  @doc "Runs selected fact handlers once, then observes the same Signal in order."
  @spec handle(t(), Jido.Signal.t()) ::
          {:ok, t(), :ok | {:error, term()}}
          | {:error, Jido.Chat.Errors.Contract.t()}
          | {:error, Jido.Chat.Errors.Contract.t(), t()}
  def handle(%__MODULE__{} = handlers, %Jido.Signal{} = signal) do
    with {:ok, signal} <- Catalog.validate(Catalog.new!(Jido.Chat.signal_definitions()), signal),
         {:ok, signal} <- Policy.validate(signal),
         {:ok, [family]} <- Router.route(handlers.family_router, signal),
         {:ok, ids} <- targets(handlers.router, signal) do
      key = {signal.source, signal.type, signal.data["delivery_id"], signal.data["item_id"]}

      if MapSet.member?(handlers.seen, key) do
        {:ok, handlers, :ok}
      else
        selected = select(handlers, signal, family, ids)

        claimed = mark_seen(handlers, key)

        case run(selected, handlers.state, signal) do
          {:ok, state} -> {:ok, %{claimed | state: state}, Dispatch.dispatch(signal, handlers.observers)}
          {:error, error, state} -> {:error, error, %{claimed | state: state}}
        end
      end
    else
      {:error, %Jido.Chat.Errors.Contract{}} = error -> error
      _ -> Policy.error(:invalid_handler_input)
    end
  end

  def handle(_handlers, _signal), do: Policy.error(:invalid_handler_input)

  defp targets(router, signal) do
    case Router.route(router, signal) do
      {:error, %{details: %{reason: :no_handlers_found}}} -> {:ok, []}
      other -> other
    end
  end

  defp select(handlers, signal, :message, ids) do
    entries = Enum.map(ids, &handlers.handlers[&1])
    subscribed = MapSet.member?(handlers.subscriptions, {signal.source, signal.subject})

    mode =
      cond do
        subscribed and Enum.any?(entries, &(&1.mode == :subscribed)) -> :subscribed
        signal.data["mentioned"] == true and Enum.any?(entries, &(&1.mode == :mention)) -> :mention
        true -> :message
      end

    Enum.filter(entries, fn entry ->
      entry.mode in [mode, :fact] and
        (is_nil(entry.pattern) or Regex.match?(entry.pattern, signal.data["text"] || ""))
    end)
  end

  defp select(handlers, _signal, _family, ids), do: Enum.map(ids, &handlers.handlers[&1])

  defp mark_seen(handlers, key) do
    order = handlers.seen_order ++ [key]
    order = Enum.take(order, -handlers.dedupe_limit)
    %{handlers | seen: MapSet.new(order), seen_order: order}
  end

  defp run(entries, state, signal) do
    Enum.reduce_while(entries, {:ok, state}, fn entry, {:ok, state} ->
      case invoke_handler(entry.callback, state, signal) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, error} -> {:halt, {:error, error, state}}
      end
    end)
  end

  defp invoke_handler(callback, state, signal) do
    if is_function(callback, 1) do
      callback.(signal)
      {:ok, state}
    else
      case callback.(state, signal) do
        {:ok, next} -> {:ok, next}
        _ -> Policy.error(:invalid_handler_result)
      end
    end
  rescue
    _ -> Policy.error(:handler_failed)
  catch
    _, _ -> Policy.error(:handler_failed)
  end
end
