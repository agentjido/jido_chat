defmodule Jido.Chat.TypedHandlersTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Delivery, Handlers}
  alias Jido.Chat.Errors.Contract
  alias Jido.Chat.Signal.{Identity, MembershipChanged, MessageReceived, SendMessage}

  defmodule Adapter do
    def signal_protocol, do: 1
    def configure_binding(opts), do: {:ok, opts}
    def normalize_event(_binding, _request), do: {:error, :invalid_delivery}
  end

  defmodule Observer do
    @behaviour Jido.Signal.Dispatch.Adapter
    def options_schema,
      do:
        Zoi.keyword([target: Zoi.pid() |> Zoi.required(), tag: Zoi.atom() |> Zoi.required()], unrecognized_keys: :error)

    def deliver(signal, opts) do
      send(opts[:target], {:observed, opts[:tag], signal})
      if opts[:tag] == :fail, do: {:error, :failed}, else: :ok
    end
  end

  setup do
    assert {:ok, binding} = Jido.Chat.bind(Adapter, id: "binding-1")
    %{binding: binding}
  end

  test "membership uses its own registered route and never enters message or mention handlers", %{binding: binding} do
    observer = self()
    assert {:ok, handlers} = Handlers.new(%{count: 0})

    assert {:ok, handlers} =
             Handlers.on(handlers, MessageReceived, fn _ -> send(observer, :message) end, mode: :message)

    assert {:ok, handlers} =
             Handlers.on(handlers, MessageReceived, fn _ -> send(observer, :mention) end, mode: :mention)

    assert {:ok, handlers} =
             Handlers.on(handlers, MembershipChanged, fn state, signal ->
               send(observer, {:membership, signal})
               {:ok, %{state | count: state.count + 1}}
             end)

    signal = membership(binding)
    before = Jido.Signal.to_map(signal)
    assert {:ok, handlers, :ok} = Handlers.handle(handlers, signal)
    assert handlers.state.count == 1
    assert_received {:membership, ^signal}
    refute_received :message
    refute_received :mention
    assert Jido.Signal.to_map(signal) == before
    assert {:ok, handlers, :ok} = Handlers.handle(handlers, signal)
    assert handlers.state.count == 1
    refute_received {:membership, _}
  end

  test "subscribed, mention, and matching-message precedence stays in application state", %{binding: binding} do
    observer = self()
    assert {:ok, handlers} = Handlers.new()

    handlers =
      Enum.reduce([:message, :mention, :subscribed], handlers, fn mode, handlers ->
        assert {:ok, next} =
                 Handlers.on(handlers, MessageReceived, fn _ -> send(observer, mode) end, mode: mode, pattern: ~r/help/)

        next
      end)

    assert {:ok, handlers, :ok} = Handlers.handle(handlers, message(binding, 1, true))
    assert_received :mention
    refute_received :message
    refute_received :subscribed
    handlers = Handlers.subscribe(handlers, binding, "room-1")
    assert {:ok, handlers, :ok} = Handlers.handle(handlers, message(binding, 2, true))
    assert_received :subscribed
    refute_received :mention
    refute_received :message
    assert {:ok, _handlers, :ok} = Handlers.handle(handlers, message(binding, 3, false, "room-2"))
    assert_received :message
  end

  test "handler registration and runner reject commands", %{binding: _binding} do
    assert {:ok, handlers} = Handlers.new()

    assert {:error, %Contract{code: :invalid_handler}} =
             Handlers.on(handlers, SendMessage, fn _ -> flunk("must not run") end)

    request = SendMessage.new!(%{"request_id" => "request-1", "room_id" => "room-1", "text" => "help"})
    assert {:error, %Contract{code: :invalid_handler_input}} = Handlers.handle(handlers, request)
  end

  test "native Dispatch observes the same accepted Signal in configured order", %{binding: binding} do
    targets = Enum.map([:first, :second], &{Observer, [target: self(), tag: &1]})
    assert {:ok, handlers} = Handlers.new(%{}, observers: targets)
    signal = membership(binding)
    assert {:ok, _handlers, :ok} = Handlers.handle(handlers, signal)
    assert_received {:observed, :first, ^signal}
    assert_received {:observed, :second, ^signal}
    refute_received {:observed, _, _}
  end

  test "observation failure does not rerun accepted handlers", %{binding: binding} do
    observer = self()
    assert {:ok, handlers} = Handlers.new(%{count: 0}, observers: [{Observer, target: self(), tag: :fail}])

    assert {:ok, handlers} =
             Handlers.on(handlers, MembershipChanged, fn state, _ ->
               send(observer, :handler_called)
               {:ok, %{state | count: state.count + 1}}
             end)

    signal = membership(binding)
    assert {:ok, next, {:error, _}} = Handlers.handle(handlers, signal)
    assert next.state.count == 1
    assert_received :handler_called
    assert_received {:observed, :fail, ^signal}
    assert {:ok, next, :ok} = Handlers.handle(next, signal)
    assert next.state.count == 1
    refute_received :handler_called
    refute_received {:observed, _, _}
  end

  test "complete delivery validation prevents any handler call on an invalid later item", %{binding: binding} do
    observer = self()
    assert {:ok, handlers} = Handlers.new()

    assert {:ok, handlers} =
             Handlers.on(handlers, MessageReceived, fn _ -> send(observer, :handled) end, mode: :message)

    valid = message(binding, 1)
    invalid = %{message(binding, 2) | data: %{"raw" => "private"}}
    delivery = %Delivery{id: "delivery-1", signals: [valid, invalid]}
    assert {:error, %Contract{}} = Handlers.accept(handlers, binding, delivery)
    refute_received :handled
  end

  test "a failed callback retains the claimed state and cannot repeat earlier work", %{binding: binding} do
    observer = self()
    assert {:ok, handlers} = Handlers.new(%{count: 0})

    assert {:ok, handlers} =
             Handlers.on(handlers, MembershipChanged, fn state, _ ->
               send(observer, :first_handler)
               {:ok, %{state | count: state.count + 1}}
             end)

    assert {:ok, handlers} = Handlers.on(handlers, MembershipChanged, fn _ -> raise "failed handler" end)
    signal = membership(binding)
    assert {:error, %Contract{code: :handler_failed}, next} = Handlers.handle(handlers, signal)
    assert next.state.count == 1
    assert_received :first_handler
    assert {:ok, next, :ok} = Handlers.handle(next, signal)
    assert next.state.count == 1
    refute_received :first_handler
  end

  test "memory deduplication has the declared bounded retention", %{binding: binding} do
    observer = self()
    assert {:ok, handlers} = Handlers.new(%{}, dedupe_limit: 1)

    assert {:ok, handlers} =
             Handlers.on(handlers, MessageReceived, fn signal -> send(observer, {:handled, signal.data["item_id"]}) end,
               mode: :message
             )

    Enum.reduce(
      [{message(binding, 1), "item-1"}, {message(binding, 2), "item-2"}, {message(binding, 1), "item-1"}],
      handlers,
      fn {signal, expected}, handlers ->
        assert {:ok, next, :ok} = Handlers.handle(handlers, signal)
        assert MapSet.size(next.seen) == 1
        assert_received {:handled, ^expected}
        next
      end
    )
  end

  defp message(binding, index, mentioned \\ false, room \\ "room-1") do
    MessageReceived.new!(
      %{
        "item_id" => "item-#{index}",
        "delivery_id" => "delivery-1",
        "room_id" => room,
        "message_id" => "message-#{index}",
        "sender" => %{"id" => "actor-1"},
        "text" => "help",
        "mentioned" => mentioned
      },
      source: binding.source,
      subject: Identity.conversation_subject(binding.id, room)
    )
  end

  defp membership(binding) do
    MembershipChanged.new!(
      %{
        "item_id" => "member-1",
        "delivery_id" => "delivery-1",
        "room_id" => "room-1",
        "participant_id" => "actor-1",
        "bot_self" => false,
        "transition" => "joined",
        "evidence" => "explicit_join",
        "previous" => nil,
        "current" => %{"status" => "member", "is_member" => true}
      },
      source: binding.source,
      subject: Identity.conversation_subject(binding.id, "room-1")
    )
  end
end
