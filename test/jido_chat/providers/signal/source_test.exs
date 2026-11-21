defmodule Jido.Chat.Signal.SourceTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Client
  alias Jido.Chat.Signal.{Adapter, Source}

  defmodule Receiver do
    def receive_messages(account, opts) do
      send(opts[:test_pid], {:received, account, opts})

      {:ok,
       [
         %{
           "envelope" => %{
             "sourceNumber" => "+15555550100",
             "timestamp" => 1,
             "dataMessage" => %{"timestamp" => 1, "message" => "hello"}
           }
         }
       ]}
    end
  end

  defmodule EmptyReceiver do
    def receive_messages(_account, _opts), do: {:ok, []}
  end

  defmodule InvalidReceiver do
    def receive_messages(_account, _opts), do: {:ok, :invalid}
  end

  defmodule ErrorReceiver do
    def receive_messages(_account, _opts), do: {:error, :provider_down}
  end

  defmodule UnsupportedReceiver do
  end

  test "reads receive batches through the shared Sensor source contract" do
    client =
      Client.new!(Adapter,
        id: "signal-source",
        credentials: %{account: "+15555550101"},
        config: [endpoint: "http://signal.test", marker: :kept]
      )

    assert {:ok, [signal], cursor} =
             Source.read(client, nil, receiver: Receiver, test_pid: self())

    assert_received {:received, "+15555550101", private}
    assert private[:endpoint] == "http://signal.test"
    assert private[:marker] == :kept
    assert private[:test_pid] == self()
    refute Keyword.has_key?(private, :account)
    refute Keyword.has_key?(private, :credentials)
    assert signal.type == "jido.chat.message.received"
    assert is_binary(cursor)
    assert Source.mode() == :poll
    assert Source.poll_interval(poll_interval_ms: 50) == 50
    assert Source.key(client, []) == Source.key(client, [])

    refute Source.key(client, []) ==
             Source.key(%{client | credentials: %{account: "+15555550102"}}, [])

    refute Source.key(client, []) ==
             Source.key(
               %{client | config: Keyword.put(client.config, :config_path, "/other")},
               []
             )
  end

  test "keeps an empty cursor and reports receive boundary errors" do
    client = Client.new!(Adapter, id: "signal-source-errors")

    assert {:ok, [], "cursor-1"} =
             Source.read(client, "cursor-1", receiver: EmptyReceiver)

    assert {:error, :invalid_receive_result} =
             Source.read(client, nil, receiver: InvalidReceiver)

    assert {:error, :provider_down} = Source.read(client, nil, receiver: ErrorReceiver)

    assert {:error, :receive_not_supported} =
             Source.read(client, nil, receiver: UnsupportedReceiver)

    assert Source.poll_interval([]) == 1_000
    assert Source.poll_interval(poll_interval_ms: 0) == 1_000

    assert Source.signal_types() == [
             "jido.chat.message.received",
             "jido.chat.normalization.failed"
           ]
  end
end
