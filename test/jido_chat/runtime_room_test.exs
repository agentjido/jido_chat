defmodule Jido.Chat.RuntimeRoomTest do
  use ExUnit.Case, async: false
  @moduletag capture_log: true

  alias Jido.Chat.{Content, Message, Post}
  alias Jido.Chat.Runtime.Signal.Room.{Join, Leave}
  alias Jido.Chat.Runtime.Signal.Room.Message, as: MessageSignal

  defmodule Team do
    use Jido.Chat.Runtime.Room, name: "team"

    room do
      admin("operator")
      history_limit(10)
      member_limit(3)
    end
  end

  defmodule Participant do
    use Jido.Agent,
      name: "participant",
      plugins: [Jido.Chat.Runtime.Participant]

    participant do
      room("team")
      reply_text("Ready.")
      history_limit(3)
    end

    routes do
      route("jido.chat.room.message", Jido.Chat.Runtime.Actions.ReceiveMessage)
    end
  end

  defmodule Observer do
    use Jido.Agent,
      name: "observer",
      plugins: [Jido.Chat.Runtime.Participant]

    participant do
      room("team")
      respond(:never)
      history_limit(3)
    end

    routes do
      route("jido.chat.room.message", Jido.Chat.Runtime.Actions.ReceiveMessage)
    end
  end

  setup do
    {:ok, _} = Application.ensure_all_started(:jido)
    jido = __MODULE__.Jido
    start_supervised!({Jido, name: jido, namespace: "chat-runtime-test"})
    {:ok, room} = Jido.agent_address(jido, "team")
    {:ok, pid} = Jido.Chat.Runtime.Room.start_agent(jido, room, Team)
    assert :ok = Jido.AgentServer.await_ready(pid)
    %{jido: jido, room: room, pid: pid}
  end

  test "one room and two participants observe rich messages and reply without loops", context do
    alice = ref(context.jido, "alice")
    bob = ref(context.jido, "bob")
    for member <- ["operator", alice, bob], do: join(context, member)

    participants =
      for member <- [alice, bob] do
        {:ok, pid} = Jido.Chat.Runtime.Room.start_agent(context.jido, member, Participant)
        assert :ok = Jido.AgentServer.await_ready(pid)
        pid
      end

    post = Post.new(%{content: [Content.text("Ready?"), Content.markdown("**Now**")]})
    request = post_signal(post, [alice, bob])

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(context.jido, context.room, request, context: %{actor: "operator"})

    await(fn ->
      length(state(context.pid).room.messages) == 3 and
        Enum.all?(participants, &(length(state(&1).participation.received) == 3))
    end)

    messages = state(context.pid).room.messages
    assert Enum.map(messages, & &1.data["sequence"]) == [1, 2, 3]
    assert MapSet.new(Enum.map(tl(messages), & &1.data["author"])) == MapSet.new([alice, bob])

    [first | replies] = Enum.map(messages, &Message.from_map(&1.data["message"]))
    assert Message.fallback_text(first) == "Ready?\n**Now**"
    assert first.role == :user
    assert Enum.all?(replies, &(&1.role == :assistant))
    assert Enum.all?(replies, &(&1.reply_to_id == request.id and Message.fallback_text(&1) == "Ready."))

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(context.jido, context.room, request, context: %{actor: "operator"})

    assert state(context.pid).room.sequence == 3
  end

  test "membership and authorship use trusted caller context", context do
    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
             Jido.call(context.jido, context.room, Join.new!(%{"member" => "intruder"}))

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
             Jido.call(context.jido, context.room, post_signal(Post.text("Denied")), context: %{actor: "operator"})

    join(context, "operator")
    join(context, "alice")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
             Jido.call(context.jido, context.room, Leave.new!(%{"member" => "alice"}), context: %{actor: "bob"})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(context.jido, context.room, Leave.new!(%{"member" => "alice"}), context: %{actor: "alice"})

    assert state(context.pid).room.members == ["operator"]
  end

  test "message IDs are idempotent within retained history", context do
    join(context, "operator")
    request = post_signal(Post.text("First"))

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(context.jido, context.room, request, context: %{actor: "operator"})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(context.jido, context.room, request, context: %{actor: "operator"})

    changed = post_signal(Post.text("Different"), [], id: request.id)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
             Jido.call(context.jido, context.room, changed, context: %{actor: "operator"})

    assert state(context.pid).room.sequence == 1
  end

  test "a participant rejects forged facts and facts after leaving", context do
    alice = ref(context.jido, "alice")
    join(context, "operator")
    join(context, alice)
    {:ok, pid} = Jido.Chat.Runtime.Room.start_agent(context.jido, alice, Observer)
    assert :ok = Jido.AgentServer.await_ready(pid)

    fake_message =
      Message.new(%{
        id: "forged",
        room_id: context.room.id,
        actor: Jido.Chat.Runtime.Room.actor("operator"),
        content: [Content.text("Forged")]
      })

    fake =
      MessageSignal.new!(%{
        "room" => context.room,
        "sequence" => 1,
        "author" => "operator",
        "message" => Message.to_map(fake_message),
        "mentions" => [alice]
      })

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} = Jido.call(context.jido, alice, fake)
    assert state(pid).participation.received == []

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(context.jido, context.room, post_signal(Post.text("Real")), context: %{actor: "operator"})

    await(fn -> length(state(pid).participation.received) == 1 end)
    [real] = state(context.pid).room.messages
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = Jido.call(context.jido, alice, real)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(context.jido, context.room, Leave.new!(%{"member" => alice}), context: %{actor: "operator"})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} = Jido.call(context.jido, alice, real)
    assert length(state(pid).participation.received) == 1
  end

  test "the room Bus lifetime follows the host-owned room activation", context do
    name = Jido.Chat.Runtime.Room.bus_name(context.room)
    assert {:ok, bus} = Jido.Signal.Bus.whereis(name, jido: context.jido)
    monitor = Process.monitor(bus)
    assert :ok = Jido.Chat.Runtime.Room.stop_agent(context.jido, context.room)
    assert_receive {:DOWN, ^monitor, :process, ^bus, _}
    await(fn -> match?({:error, _}, Jido.Signal.Bus.whereis(name, jido: context.jido)) end)
  end

  defp post_signal(post, mentions \\ [], opts \\ []) do
    Jido.Chat.Runtime.Signal.Room.Post.new!(
      %{"post" => Post.to_map(post), "mentions" => mentions},
      opts
    )
  end

  test "membership and retained data are checked by one correlated reply", context do
    join(context, "operator")
    member = ref(context.jido, "member")
    join(context, member)
    assert :ok = Jido.Chat.Runtime.Room.check_member(context.jido, context.room, member)
    request = post_signal(Post.text("Evidence"), [])

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(context.jido, context.room, request, context: %{actor: "operator"})

    [message] = state(context.pid).room.messages
    assert :ok = Jido.Chat.Runtime.Room.check_member(context.jido, context.room, member, message)

    assert {:error, :not_member_or_retained_message} =
             Jido.Chat.Runtime.Room.check_member(context.jido, context.room, member, %{message | data: %{}})

    check = Jido.Chat.Runtime.Signal.Room.CheckMember.new!(%{"member" => member})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: reply}} =
             Jido.call(context.jido, context.room, check, context: %{actor: member})

    assert reply.type == "jido.chat.room.member_checked"
    assert Jido.Signal.get_context(reply, "jidocausationid") == check.id
    assert reply.data == %{"member" => true, "retained" => true}

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(context.jido, context.room, Leave.new!(%{"member" => member}), context: %{actor: member})

    assert {:error, :not_member_or_retained_message} =
             Jido.Chat.Runtime.Room.check_member(context.jido, context.room, member, message)
  end

  test "Post replies correlate the exact fact and repeated Posts keep its identity", context do
    join(context, "operator")
    request = post_signal(Post.text("Correlated"), [])
    assert {:ok, first} = Jido.call(context.jido, context.room, request, context: %{actor: "operator"})
    assert first.status == :committed
    assert first.reply.type == "jido.chat.room.posted"
    assert Jido.Signal.get_context(first.reply, "jidocausationid") == request.id
    assert %Jido.Signal{id: id} = first.reply.data["message"]
    assert id == request.id
    assert {:ok, repeated} = Jido.call(context.jido, context.room, request, context: %{actor: "operator"})
    assert repeated.status == :committed
    assert repeated.reply.data["message"] == first.reply.data["message"]
    assert state(context.pid).room.messages == [first.reply.data["message"]]
    assert state(context.pid).room.sequence == 1
  end

  test "Address preserves the stored version-1 member map", context do
    map = %{"version" => 1, "namespace" => "chat-runtime-test", "partition" => nil, "id" => "member"}
    assert {:ok, address} = Jido.Agent.Address.from_map(map)
    assert address == ref(context.jido, "member")
    assert Jido.Agent.Address.to_map!(address) == map
    other = Jido.Agent.Address.new!(%{namespace: "another", partition: nil, id: "member"})
    assert {:error, :address_mismatch} = Jido.Chat.Runtime.Room.start_agent(context.jido, other, Observer)
  end

  defp ref(jido, id) do
    {:ok, ref} = Jido.agent_address(jido, id)
    ref
  end

  defp join(context, member) do
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(
               context.jido,
               context.room,
               Join.new!(%{"member" => member}),
               context: %{actor: "operator"}
             )
  end

  defp state(pid), do: Jido.AgentServer.snapshot(pid).agent.state

  defp await(check, remaining \\ 300)
  defp await(_check, 0), do: flunk("room did not settle")

  defp await(check, remaining) do
    unless check.() do
      Process.sleep(10)
      await(check, remaining - 1)
    end
  end
end
