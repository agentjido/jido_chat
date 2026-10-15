defmodule Jido.Chat.RequestStoreTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.{RequestStore, Signal.SendMessage}
  alias Jido.Chat.Errors.Contract
  alias Jido.Chat.Operations.Failure

  defmodule Adapter do
    use Jido.Chat.Adapter
    def signal_protocol, do: 1
    def configure_binding(opts), do: {:ok, opts}
    def normalize_event(_binding, _raw), do: {:error, :unused}
    def capabilities, do: %{send_message: :native}

    def send_message(room, text, opts) do
      send(opts[:probe], {:provider, opts})
      {:ok, %{id: "sent", room_id: room, text: text}}
    end
  end

  defmodule Backend do
    alias Jido.Chat.Signal.Policy
    def claim(:unavailable, _key, _digest), do: Policy.error(:request_outcome_unknown)
    def claim({:completion_failure, table}, key, digest), do: claim(table, key, digest)

    def claim(table, key, digest) do
      if :ets.insert_new(table, {key, digest, :running}) do
        {:ok, {key, digest}}
      else
        case :ets.lookup(table, key) do
          [{^key, ^digest, {:done, result}}] -> {:cached, result}
          [{^key, ^digest, :running}] -> Policy.error(:request_in_progress)
          _ -> Policy.error(:request_conflict)
        end
      end
    end

    def complete({:completion_failure, _table}, _claim, _result), do: Policy.error(:request_outcome_unknown)

    def complete(table, {key, digest}, result) do
      :ets.insert(table, {key, digest, {:done, result}})
      :ok
    end

    def outcome(:unavailable, _claim), do: Policy.error(:request_outcome_unknown)
    def outcome({:completion_failure, table}, claim), do: outcome(table, claim)

    def outcome(table, {key, digest}) do
      case :ets.lookup(table, key) do
        [{^key, ^digest, :running}] -> :ok
        [{^key, ^digest, {:done, result}}] -> {:cached, result}
        _ -> Policy.error(:request_outcome_unknown)
      end
    end

    def remember(table, id, class, tag) do
      :ets.insert(table, {{:failure, id}, class, tag})
      :ok
    end

    def failure(:unavailable, _id), do: Policy.error(:request_outcome_unknown)

    def failure(table, id) do
      case :ets.lookup(table, {:failure, id}) do
        [{_, class, tag}] -> {:ok, {class, tag}}
        [] -> {:error, :not_found}
      end
    end
  end

  setup do
    {:ok, binding} = Jido.Chat.bind(Adapter, id: "owned", probe: self())
    %{binding: binding, backend: :ets.new(:test_backend, [:set, :public])}
  end

  test "owned backend keeps exact replay and stays out of provider options", context do
    assert :ok = RequestStore.install(context.binding, {Backend, context.backend})
    request = request("one")
    assert {:ok, result} = Jido.Chat.execute(context.binding, request)
    assert_received {:provider, [probe: probe]}
    assert probe == self()
    assert {:ok, ^result} = Jido.Chat.execute(context.binding, request)
    refute_received {:provider, _}
    assert :ets.info(context.binding.resources, :size) == 1
    assert :ets.info(context.backend, :size) == 1

    assert {:error, %Contract{code: :request_conflict}} =
             Jido.Chat.execute(context.binding, %{request | data: Map.put(request.data, "text", "changed")})
  end

  test "installation requires an empty table owned by this process", context do
    task = Task.async(fn -> RequestStore.install(context.binding, {Backend, context.backend}) end)
    assert {:error, %Contract{code: :invalid_binding}} = Task.await(task)
    assert {:ok, _} = Jido.Chat.execute(context.binding, request("standalone"))

    assert {:error, %Contract{code: :invalid_binding}} =
             RequestStore.install(context.binding, {Backend, context.backend})

    :ets.delete(context.binding.resources)

    assert {:error, %Contract{code: :invalid_binding}} =
             RequestStore.install(context.binding, {Backend, context.backend})
  end

  test "backend errors preserve contract failures at claim and completion", context do
    :ok = RequestStore.install(context.binding, {Backend, :unavailable})
    assert {:error, %Contract{code: :request_outcome_unknown}} = Jido.Chat.execute(context.binding, request("claim"))
    refute_received {:provider, _}
    {:ok, binding} = Jido.Chat.bind(Adapter, id: "completion", probe: self())
    :ok = RequestStore.install(binding, {Backend, {:completion_failure, context.backend}})
    assert {:error, %Contract{code: :request_outcome_unknown}} = Jido.Chat.execute(binding, request("complete"))
    assert_received {:provider, _}
  end

  test "failure class and reason tag use the backend and support replacement", context do
    :ok = RequestStore.install(context.binding, {Backend, context.backend})
    result = %{id: "failure", data: %{"retryable" => true}}
    assert Failure.class(context.binding, result) == :recoverable
    assert Failure.reason_tag(context.binding, result) == nil
    :ok = Failure.remember(context.binding, result, :degraded, :load_shed)
    assert Failure.class(context.binding, result) == :degraded
    assert Failure.reason_tag(context.binding, result) == :load_shed
    :ok = Failure.remember(context.binding, result, :fatal, nil)
    assert Failure.class(context.binding, result) == :fatal
    assert Failure.reason_tag(context.binding, result) == nil
    assert :ets.info(context.binding.resources, :size) == 1
  end

  test "unavailable failure metadata cannot permit a provider retry", context do
    :ok = RequestStore.install(context.binding, {Backend, :unavailable})
    result = %{id: "failure", data: %{"retryable" => true}}
    assert Failure.class(context.binding, result) == :fatal
    assert Failure.reason_tag(context.binding, result) == nil
  end

  defp request(id), do: SendMessage.new!(%{"request_id" => id, "room_id" => "room", "text" => "hello"})
end
