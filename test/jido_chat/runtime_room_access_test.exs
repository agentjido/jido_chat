defmodule Jido.Chat.RuntimeRoomAccessTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.Post
  alias Jido.Chat.Runtime.Signal.Room.{Join, Posted}
  alias Jido.Chat.Runtime.Signal.Room.Post, as: PostSignal

  defmodule HostIdentity do
    @behaviour Jido.Chat.IdentityProvider

    @impl true
    def resolve(%{provider: "assembly", account_id: "tenant-a", external_id: external_id}, _context) do
      case external_id do
        "external-admin" -> {:ok, %{id: "operator", kind: :human, assurance: :verified}}
        "external-alice" -> {:ok, %{id: "alice", kind: :human, assurance: :verified}}
        _other -> {:error, :identity_not_found}
      end
    end

    def resolve(_source, _context), do: {:error, :identity_scope_denied}
  end

  defmodule SecuredRoom do
    use Jido.Chat.Runtime.Room, name: "secured-room"

    room do
      admin("operator")
      identity_provider(HostIdentity)
      authorizer(Jido.Chat.Authorizer.Room)
    end
  end

  setup do
    {:ok, _} = Application.ensure_all_started(:jido)
    jido = __MODULE__.Jido
    start_supervised!({Jido, name: jido, namespace: "chat-room-access-test"})
    {:ok, room} = Jido.agent_address(jido, "secured-room")
    {:ok, pid} = Jido.Chat.Runtime.Room.start_agent(jido, room, SecuredRoom)
    assert :ok = Jido.AgentServer.await_ready(pid)
    %{jido: jido, room: room, pid: pid}
  end

  test "an external identity provider controls Room membership and authorship", context do
    assert committed(context, Join.new!(%{"member" => "operator"}), "external-admin", "spoofed")
    assert committed(context, Join.new!(%{"member" => "alice"}), "external-admin", "spoofed")

    request = PostSignal.new!(%{"post" => Post.to_map(Post.text("Hello")), "mentions" => []})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, reply: %Jido.Signal{} = reply}} =
             Jido.call(context.jido, context.room, request, context: access_context("external-alice", "spoofed"))

    assert reply.type == Posted.type()
    [message] = Jido.AgentServer.snapshot(context.pid).agent.state.room.messages
    assert message.data["author"] == "alice"
  end

  test "unknown, cross-room, and unauthorized identities fail closed", context do
    assert failed(context, Join.new!(%{"member" => "alice"}), "external-alice")
    assert failed(context, Join.new!(%{"member" => "alice"}), "unknown")

    bad_context =
      access_context("external-admin", "operator")
      |> put_in([:identity_source, :room_id], "another-room")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
             Jido.call(context.jido, context.room, Join.new!(%{"member" => "alice"}), context: bad_context)

    assert Jido.AgentServer.snapshot(context.pid).agent.state.room.members == []
  end

  defp committed(context, signal, external_id, actor) do
    match?(
      {:ok, %Jido.AgentServer.TurnResult{status: :committed}},
      Jido.call(context.jido, context.room, signal, context: access_context(external_id, actor))
    )
  end

  defp failed(context, signal, external_id) do
    match?(
      {:ok, %Jido.AgentServer.TurnResult{status: :failed}},
      Jido.call(context.jido, context.room, signal, context: access_context(external_id, "spoofed"))
    )
  end

  defp access_context(external_id, actor) do
    %{
      actor: actor,
      identity_source: %{
        provider: "assembly",
        account_id: "tenant-a",
        external_id: external_id,
        room_id: "secured-room"
      }
    }
  end
end
