defmodule Jido.Chat.AuthenticationTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.{Adapter, CapabilityMatrix}

  defmodule Legacy do
    use Jido.Chat.Adapter
    def channel_type, do: :legacy
    def transform_incoming(_), do: {:error, :unused}
    def send_message(_, _, _), do: {:error, :unused}
  end

  defmodule QRProvider do
    def authenticate(request, owner, opts) do
      send(opts[:observer], {request, owner, opts})
      Keyword.fetch!(opts, :result)
    end
  end

  defmodule Declared do
    def send_message(_, _, _), do: {:error, :unused}
    def capabilities, do: %{authenticate: :native}
    def authenticate(_, _, _), do: {:ok, %{phase: :pending}}
  end

  defmodule Missing do
    def capabilities, do: %{authenticate: :native}
  end

  defmodule Contradictory do
    def capabilities, do: %{authenticate: :unsupported}
    def authenticate(_, _, _), do: raise("must not invoke")
  end

  test "legacy adapters stay valid and unsupported" do
    assert Adapter.capabilities(Legacy).authenticate == :unsupported
    assert :ok = Adapter.validate_capabilities(Legacy)
    assert {:error, :unsupported} = Adapter.authenticate(Legacy, %{op: :begin}, :owner)
  end

  test "existing matrix infers and validates authentication" do
    assert Adapter.capabilities(QRProvider).authenticate == :native
    assert CapabilityMatrix.status(Adapter.capability_matrix(Declared), :authenticate) == :native
    assert :ok = Adapter.validate_capabilities(Declared)
    assert {:error, {:invalid_capability_matrix, errors}} = Adapter.validate_capabilities(Missing)
    assert {:authenticate, :missing_callback} in errors
    assert {:error, {:invalid_capability_matrix, errors}} = Adapter.validate_capabilities(Contradictory)
    assert {:authenticate, :unsupported_callback} in errors
    assert {:error, :unsupported} = Adapter.authenticate(Contradictory, %{op: :begin}, :owner)
  end

  test "all operations preserve owner, opaque handle, trusted options and callback results" do
    session = {:another_provider, make_ref()}

    for op <- [:begin, :status, :retry, :confirm, :cancel],
        result <- [{:ok, %{phase: :pending, session: session}}, {:error, :identity_changed}] do
      request = %{op: op, session: session, account_id: "account"}
      opts = [observer: self(), context: %{private: true}, result: result]
      assert Adapter.authenticate(QRProvider, request, :owner, opts) == result
      assert_received {^request, :owner, ^opts}
    end
  end

  test "malformed requests never reach the callback" do
    for request <- [
          nil,
          %{},
          %{op: :other},
          %{op: :status},
          %{op: :retry, session: nil},
          %{op: :confirm, session: :handle},
          %{op: :confirm, session: :handle, account_id: ""}
        ] do
      assert {:error, :invalid_request} = Adapter.authenticate(QRProvider, request, :owner, [])
    end

    assert {:error, :invalid_request} = Adapter.authenticate(QRProvider, %{op: :begin}, nil, [])
    assert {:error, :invalid_request} = Adapter.authenticate(QRProvider, %{op: :begin}, :owner, [:bad])
    refute_received {_, _, _}
  end
end
