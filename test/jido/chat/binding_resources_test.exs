defmodule Jido.Chat.BindingResourcesTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Errors.Contract

  defmodule Adapter do
    def signal_protocol, do: 1
    def configure_binding(opts), do: {:ok, opts}
    def normalize_event(_binding, _request), do: {:error, :not_implemented}
  end

  defmodule Incompatible do
    def signal_protocol, do: 2
    def configure_binding(_opts), do: raise("must not start incompatible setup")
    def normalize_event(_binding, _request), do: {:error, :not_implemented}
  end

  test "bind rejects an incompatible adapter before configured setup" do
    assert {:error, %Contract{code: :incompatible_protocol}} = Jido.Chat.bind(Incompatible, id: "binding-1")
    assert {:error, %Contract{code: :invalid_binding}} = Jido.Chat.bind(Adapter, id: "")
  end

  test "a scoped resource preserves bytes privately and cancellation removes their value" do
    assert {:ok, binding} = Jido.Chat.bind(Adapter, id: "binding-1", token: "private-token")
    assert binding.source == Jido.Chat.Signal.Identity.binding_source("binding-1")
    assert {:ok, ref} = Jido.Chat.put_resource(binding, "file", <<255, 0, 1>>)
    assert {:ok, <<255, 0, 1>>} = Jido.Chat.resolve_resource(binding, ref)
    refute Map.has_key?(ref, "value")
    refute Map.has_key?(ref, "token")
    assert :ok = Jido.Chat.cancel_resource(binding, ref)
    assert {:error, %Contract{code: :resource_cancelled}} = Jido.Chat.resolve_resource(binding, ref)
    assert [{{:resource, _}, _, _, nil, _, :cancelled}] = :ets.tab2list(binding.resources)
  end

  test "expiry, closed storage, owner mismatch, and binding mismatch fail explicitly" do
    assert {:ok, binding} = Jido.Chat.bind(Adapter, id: "binding-1")
    assert {:ok, expired} = Jido.Chat.put_resource(binding, "media", "private", ttl_ms: 0)
    assert {:error, %Contract{code: :resource_expired}} = Jido.Chat.resolve_resource(binding, expired)
    assert {:ok, ref} = Jido.Chat.put_resource(binding, "file", "private")
    task = Task.async(fn -> Jido.Chat.resolve_resource(binding, ref) end)
    assert {:error, %Contract{code: :resource_owner_mismatch}} = Task.await(task)

    assert {:error, %Contract{code: :invalid_resource}} =
             Jido.Chat.resolve_resource(binding, %{ref | "binding_id" => "other"})

    assert :ok = Jido.Chat.Resources.close(binding)
    assert {:error, %Contract{code: :resource_expired}} = Jido.Chat.resolve_resource(binding, ref)
  end

  test "stream storage and resolution do not enumerate the stream" do
    assert {:ok, binding} = Jido.Chat.bind(Adapter, id: "binding-1")
    observer = self()

    stream =
      Stream.map(["one", "two"], fn item ->
        send(observer, {:enumerated, item})
        item
      end)

    assert {:ok, ref} = Jido.Chat.put_resource(binding, "stream", stream)
    assert {:ok, ^stream} = Jido.Chat.resolve_resource(binding, ref)
    refute_received {:enumerated, _}
    assert Enum.to_list(stream) == ["one", "two"]
    assert_received {:enumerated, "one"}
    assert_received {:enumerated, "two"}
  end

  test "a completed creator call cannot leave its private value available" do
    scope = %{id: "runtime-owner", resources: :ets.new(:call_resources, [:set, :public])}
    task = Task.async(fn -> Jido.Chat.Resources.put(scope, "result", "private-result", []) end)
    assert {:ok, ref} = Task.await(task)
    assert {:error, %Contract{code: :resource_expired}} = Jido.Chat.Resources.resolve(scope, ref)
    assert [{{:resource, _}, _, "result", nil, _, :expired}] = :ets.lookup(scope.resources, {:resource, ref["id"]})
  end

  test "expiry clears a private value even when a different caller checks it" do
    assert {:ok, binding} = Jido.Chat.bind(Adapter, id: "binding-1")
    assert {:ok, ref} = Jido.Chat.put_resource(binding, "result", "private-result", ttl_ms: 0)
    task = Task.async(fn -> Jido.Chat.resolve_resource(binding, ref) end)
    assert {:error, %Contract{code: :resource_expired}} = Task.await(task)
    assert [{{:resource, _}, _, "result", nil, _, :expired}] = :ets.lookup(binding.resources, {:resource, ref["id"]})
  end

  test "a resource kind mismatch cannot reuse a terminal resource state" do
    assert {:ok, binding} = Jido.Chat.bind(Adapter, id: "binding-1")
    assert {:ok, ref} = Jido.Chat.put_resource(binding, "result", "private-result")
    assert :ok = Jido.Chat.cancel_resource(binding, ref)
    assert {:error, %Contract{code: :invalid_resource}} = Jido.Chat.resolve_resource(binding, %{ref | "kind" => "file"})
  end

  test "invalid resource inputs and closed storage cannot retain private values" do
    assert {:ok, binding} = Jido.Chat.bind(Adapter, id: "invalid-resources")

    for {kind, opts} <- [{"unknown", []}, {"file", [ttl_ms: -1]}, {"file", [ttl_ms: :invalid]}, {"file", [:invalid]}] do
      assert {:error, %Contract{code: :invalid_resource}} = Jido.Chat.put_resource(binding, kind, "private", opts)
    end

    assert :ets.tab2list(binding.resources) == []
    assert {:error, %Contract{code: :invalid_resource}} = Jido.Chat.put_resource(nil, "file", "private")
    assert {:ok, ref} = Jido.Chat.put_resource(binding, "file", "private")

    assert {:error, %Contract{code: :invalid_resource}} =
             Jido.Chat.resolve_resource(binding, %{ref | "id" => "missing"})

    assert :ok = Jido.Chat.Resources.close(binding)
    assert :ok = Jido.Chat.Resources.close(binding)
    assert {:error, %Contract{code: :resource_expired}} = Jido.Chat.put_resource(binding, "file", "private")
  end
end
