defmodule Jido.Chat.HostContractTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Adapter, Authentication, Storage}

  defmodule Legacy do
    def channel_type, do: :legacy
  end

  defmodule OtherProvider do
    def prepare_connection(_opts), do: {:ok, %{prepared: true}}
    def provider_child_specs(_opts), do: {:ok, []}
    def connection_identity(binding), do: {:ok, {:other, binding}}
    def connection_options(binding, _opts), do: %{scope: binding}
    def logout(listener), do: send(listener, :logged_out) && :ok
  end

  test "legacy adapters retain startup and delivery options without adopting optional features" do
    opts = [token: "opaque"]
    assert {:ok, ^opts} = Adapter.prepare_connection(Legacy, opts)
    assert {:ok, []} = Adapter.provider_child_specs(Legacy, [])
    assert {:ok, ^opts} = Adapter.connection_options(Legacy, nil, opts)
    assert {:error, :unsupported} = Adapter.connection_identity(Legacy, :binding)
    assert {:error, :unsupported} = Adapter.logout(Legacy, self())
  end

  test "a non-WhatsApp provider uses the same preparation, scope and logout contracts" do
    assert {:ok, [ingress: %{prepared: true}]} = Adapter.prepare_connection(OtherProvider, [])
    assert {:ok, []} = Adapter.provider_child_specs(OtherProvider, [])
    assert {:ok, {:other, :binding}} = Adapter.connection_identity(OtherProvider, :binding)
    assert {:ok, opts} = Adapter.connection_options(OtherProvider, :binding, token: "opaque")
    assert opts[:scope] == :binding
    assert opts[:token] == "opaque"
    assert :ok = Adapter.logout(OtherProvider, self())
    assert_received :logged_out
  end

  test "shared authentication requests preserve the sole sink shape and redact secrets" do
    sink = {__MODULE__, :observe, [self(), {:ok, :receipt}]}
    assert {:ok, :receipt} = Authentication.Request.call(sink, :private_actor, %{op: :persist})
    assert_received {%Authentication.Request{context: :private_actor, id: id} = event, []}
    assert is_reference(id)
    refute inspect(event) =~ "private_actor"
    assert {:error, :invalid_pairing_request} = Authentication.Request.call(sink, nil, %{op: :unknown})
    refute_received {_, _}
  end

  test "storage preserves absence, errors and commit acknowledgement without runtime processes" do
    for result <- [:error, :ok, {:ok, "opaque"}, {:error, :revoked}] do
      assert ^result = Storage.Request.call({__MODULE__, :observe, [self(), result]}, :private_binding, %{op: :get})
      assert_received {%Storage.Request{binding: :private_binding} = event, []}
      refute inspect(event) =~ "private_binding"
    end

    assert {:error, :invalid_storage_request} = Storage.Request.call(nil, nil, %{op: :get})

    assert {:error, :invalid_storage_request} =
             Storage.Request.call({__MODULE__, :observe, [self(), :ok]}, nil, %{op: :unknown})

    refute_received {_, _}
  end

  test "exceptions and unsanitized failures do not cross the shared sink boundary" do
    assert {:error, :storage_unavailable} = Storage.Request.call({__MODULE__, :crash, []}, nil, %{op: :put})
    assert {:error, :callback_failed} = Authentication.Request.call({__MODULE__, :crash, []}, nil, %{op: :start})

    assert {:error, :storage_unavailable} =
             Storage.Request.call({__MODULE__, :observe, [self(), {:error, "secret"}]}, nil, %{op: :put})
  end

  def observe(observer, result, event, opts) do
    send(observer, {event, opts})
    result
  end

  def crash(_, _), do: raise("secret")
end
