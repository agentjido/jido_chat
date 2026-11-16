defmodule Jido.Chat.RuntimeStorageTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Runtime.Storage
  alias Jido.Chat.Runtime.Storage.{Adapter, Commit, Links, Memory, Outbox}

  defmodule LinksOnly do
    use Adapter, capabilities: [Links]

    @impl Links
    def put_link(_resource, link), do: {:ok, link}

    @impl Links
    def link_for_local(_resource, _account_id, _local_id), do: {:ok, nil}

    @impl Links
    def link_for_external(_resource, _account_id, _room_id, _message_id), do: {:ok, nil}
  end

  defmodule CallbackOnly do
    def put_link(_resource, link), do: {:ok, link}
    def link_for_local(_resource, _account_id, _local_id), do: {:ok, nil}
    def link_for_external(_resource, _account_id, _room_id, _message_id), do: {:ok, nil}
  end

  defmodule FalseDeclaration do
    def __storage_capabilities__, do: [Links]
  end

  setup do
    start_supervised!(Memory)
    |> then(&%{storage: &1})
  end

  test "Memory implements every merge-scope capability", %{storage: storage} do
    assert :ok == Storage.validate({Memory, storage}, [Links, Outbox, Commit])
    assert Storage.capabilities(Memory) == [Links, Outbox, Commit]
  end

  test "adapter declarations are additive and checked against callbacks" do
    assert :ok = Storage.validate({LinksOnly, :resource}, [Links])

    assert {:error, :unsupported_storage_capability} =
             Storage.validate({LinksOnly, :resource}, [Outbox])

    assert :ok = Storage.validate({CallbackOnly, :resource}, [Links])

    assert {:error, :unsupported_storage_capability} =
             Storage.validate({FalseDeclaration, :resource}, [Links])
  end

  test "links are available by local and provider identity", %{storage: storage} do
    link = %{
      account_id: "support",
      local_message_id: "local-1",
      external_room_id: "provider-room",
      external_message_id: "provider-1"
    }

    assert {:ok, ^link} = Memory.put_link(storage, link)
    assert {:ok, ^link} = Memory.link_for_local(storage, "support", "local-1")
    assert {:ok, ^link} = Memory.link_for_external(storage, "support", "provider-room", "provider-1")
  end

  test "outbox enforces explicit delivery transitions", %{storage: storage} do
    work = %{id: "work-1", account_id: "support", status: :pending, payload: %{}}

    assert {:ok, ^work} = Memory.put_work(storage, work)
    assert {:ok, claimed} = Memory.update_work(storage, "work-1", :pending, %{status: :claimed})
    assert claimed.status == :claimed

    assert {:ok, submitted} =
             Memory.update_work(storage, "work-1", :claimed, %{status: :submitted})

    assert submitted.status == :submitted

    assert {:error, :invalid_work_transition} =
             Memory.update_work(storage, "work-1", :submitted, %{status: :pending})

    assert {:ok, completed} =
             Memory.update_work(storage, "work-1", :submitted, %{
               status: :completed,
               result: %{"id" => "provider-1"}
             })

    assert completed.status == :completed
    assert {:ok, [^completed]} = Memory.list_work(storage, "support", status: :completed)
  end

  test "commit applies all commands or none", %{storage: storage} do
    link = %{
      account_id: "support",
      local_message_id: "local-atomic",
      external_room_id: "provider-room",
      external_message_id: "provider-atomic"
    }

    assert {:error, :invalid_work} =
             Memory.commit(storage, [
               {:put_link, link},
               {:put_work, %{id: "bad", account_id: "support", status: :invalid}}
             ])

    assert {:ok, nil} = Memory.link_for_local(storage, "support", "local-atomic")

    work = %{id: "work-atomic", account_id: "support", status: :pending}

    assert {:ok, [^link, ^work]} =
             Memory.commit(storage, [
               {:put_link, link},
               {:put_work, work}
             ])

    assert {:ok, ^link} = Memory.link_for_local(storage, "support", "local-atomic")
    assert {:ok, ^work} = Memory.get_work(storage, "work-atomic")
  end
end
