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
      extensions: [Jido.Chat.Runtime.Participant]

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
      extensions: [Jido.Chat.Runtime.Participant]

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
    {:ok, room} = Jido.agent_ref(jido, "team")
    {:ok, pid} = Jido.start_agent_ref(jido, room, Team)
    assert :ok = Jido.AgentServer.await_ready(pid)
    %{jido: jido, room: room, pid: pid}
  end

  test "one room and two participants observe rich messages and reply without loops", context do
    alice = ref(context.jido, "alice")
    bob = ref(context.jido, "bob")
    for member <- ["operator", alice, bob], do: join(context, member)

    participants =
      for member <- [alice, bob] do
        {:ok, pid} = Jido.start_agent_ref(context.jido, member, Participant)
        assert :ok = Jido.AgentServer.await_ready(pid)
        pid
      end

    post = Post.new(%{content: [Content.text("Ready?"), Content.markdown("**Now**")]})
    request = post_signal(post, [alice, bob])
    assert {:ok, _, _} = Jido.call(context.jido, context.room, request, context: %{actor: "operator"})

    await(fn ->
      length(state(context.pid).room.messages) == 3 and
        Enum.all?(participants, &(length(state(&1).participation.received) == 3))
    end)

    messages = state(context.pid).room.messages
    assert Enum.map(messages, & &1.data["sequence"]) == [1, 2, 3]
    assert MapSet.new(Enum.map(tl(messages), & &1.data["author"])) == MapSet.new([alice, bob])

    [first | replies] = Enum.map(messages, &Message.from_map(&1.data["message"]))
    assert Message.fallback_text(first) == "Ready?\n**Now**"
    assert Enum.all?(replies, &(&1.reply_to_id == request.id and Message.fallback_text(&1) == "Ready."))

    assert {:ok, _, []} = Jido.call(context.jido, context.room, request, context: %{actor: "operator"})
    assert state(context.pid).room.sequence == 3
  end

  test "membership and authorship use trusted caller context", context do
    assert {:error, _} = Jido.call(context.jido, context.room, Join.new!(%{"member" => "intruder"}))

    assert {:error, _} =
             Jido.call(context.jido, context.room, post_signal(Post.text("Denied")), context: %{actor: "operator"})

    join(context, "operator")
    join(context, "alice")

    assert {:error, _} =
             Jido.call(context.jido, context.room, Leave.new!(%{"member" => "alice"}), context: %{actor: "bob"})

    assert {:ok, _, _} =
             Jido.call(context.jido, context.room, Leave.new!(%{"member" => "alice"}), context: %{actor: "alice"})

    assert state(context.pid).room.members == ["operator"]
  end

  test "message IDs are idempotent within retained history", context do
    join(context, "operator")
    request = post_signal(Post.text("First"))

    assert {:ok, _, _} = Jido.call(context.jido, context.room, request, context: %{actor: "operator"})
    assert {:ok, _, []} = Jido.call(context.jido, context.room, request, context: %{actor: "operator"})

    changed = post_signal(Post.text("Different"), [], id: request.id)
    assert {:error, _} = Jido.call(context.jido, context.room, changed, context: %{actor: "operator"})
    assert state(context.pid).room.sequence == 1
  end

  test "a participant rejects forged facts and facts after leaving", context do
    alice = ref(context.jido, "alice")
    join(context, "operator")
    join(context, alice)
    {:ok, pid} = Jido.start_agent_ref(context.jido, alice, Observer)
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

    assert {:error, _} = Jido.call(context.jido, alice, fake)
    assert state(pid).participation.received == []

    assert {:ok, _, _} =
             Jido.call(context.jido, context.room, post_signal(Post.text("Real")), context: %{actor: "operator"})

    await(fn -> length(state(pid).participation.received) == 1 end)
    [real] = state(context.pid).room.messages
    assert {:ok, _, []} = Jido.call(context.jido, alice, real)

    assert {:ok, _, _} =
             Jido.call(context.jido, context.room, Leave.new!(%{"member" => alice}), context: %{actor: "operator"})

    assert {:error, _} = Jido.call(context.jido, alice, real)
    assert length(state(pid).participation.received) == 1
  end

  test "the room Bus lifetime follows the host-owned room activation", context do
    name = Jido.Chat.Runtime.Room.bus_name(context.room)
    assert {:ok, bus} = Jido.Signal.Bus.whereis(name, jido: context.jido)
    monitor = Process.monitor(bus)
    assert :ok = Jido.stop_agent_ref(context.jido, context.room)
    assert_receive {:DOWN, ^monitor, :process, ^bus, _}
    await(fn -> match?({:error, _}, Jido.Signal.Bus.whereis(name, jido: context.jido)) end)
  end

  defp post_signal(post, mentions \\ [], opts \\ []) do
    Jido.Chat.Runtime.Signal.Room.Post.new!(
      %{"post" => Post.to_map(post), "mentions" => mentions},
      opts
    )
  end

  defp ref(jido, id) do
    {:ok, ref} = Jido.agent_ref(jido, id)
    ref
  end

  defp join(context, member) do
    assert {:ok, _, _} =
             Jido.call(
               context.jido,
               context.room,
               Join.new!(%{"member" => member}),
               context: %{actor: "operator"}
             )
  end

  defp state(pid), do: Jido.AgentServer.agent(pid).state

  defp await(check, remaining \\ 300)
  defp await(_check, 0), do: flunk("room did not settle")

  defp await(check, remaining) do
    unless check.() do
      Process.sleep(10)
      await(check, remaining - 1)
    end
  end
end
