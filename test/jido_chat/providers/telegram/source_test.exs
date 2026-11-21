defmodule Jido.Chat.Telegram.SourceTest do
  use ExUnit.Case, async: false
  @moduletag capture_log: true
  alias Jido.Chat.Telegram.Source

  defmodule Transport do
    def call(_token, "getUpdates", payload, opts) do
      send(opts[:observer], {:fetch, payload})
      opts[:result] || {:ok, opts[:updates] || []}
    end
  end

  defp client(opts \\ []) do
    Jido.Chat.Client.new!(Jido.Chat.Telegram.Adapter,
      id: "source-test",
      credentials: %{token: "source-test-secret"},
      transport: Transport,
      config: Keyword.put(opts, :observer, self())
    )
  end

  defp update(id, key \\ "message") do
    %{
      "update_id" => id,
      key => %{
        "message_id" => 5,
        "chat" => %{"id" => 123, "type" => "private"},
        "from" => %{"id" => 42, "is_bot" => false},
        "text" => "hello"
      }
    }
  end

  test "reads typed facts through FetchUpdates and returns the next cursor" do
    c = client(updates: [update(10), update(11, "edited_message")])
    assert {:ok, signals, 12} = Source.read(c, 10, limit: 20)
    assert Enum.map(signals, & &1.type) == ["jido.chat.message.received", "jido.chat.message.updated"]
    assert Enum.all?(signals, &(&1.source == c.source))
    assert_receive {:fetch, %{"offset" => 10, "limit" => 20, "timeout" => 0, "allowed_updates" => allowed}}
    assert "message_reaction" in allowed
    assert "callback_query" in allowed
  end

  test "empty batches retain the cursor and initial reads omit the offset" do
    assert {:ok, [], nil} = Source.read(client(), nil, [])
    assert_receive {:fetch, payload}
    refute Map.has_key?(payload, "offset")
    assert {:ok, [], 9} = Source.read(client(), 9, [])
  end

  test "invalid read options fail before transport; provider failures return errors" do
    assert {:error, _} = Source.read(client(), nil, limit: 0)
    refute_receive {:fetch, _}
    assert {:error, _} = Source.read(client(result: {:error, :offline}), 2, [])
    assert_receive {:fetch, _}
  end

  test "polling identity hashes credentials and is shared across client IDs" do
    c = client()
    key = Source.key(c, [])
    assert byte_size(key) == 32
    refute key == c.credentials.token
    assert Source.key(%{c | id: "other"}, []) == key
    assert Source.key(%{c | credentials: %{}}, []) == nil
    assert Source.key(%{c | credentials: %{token: ""}}, []) == nil
  end

  test "the generic Sensor delivers Telegram facts to a PID without a Jido Agent" do
    c = client(updates: [update(10)])

    pid =
      start_supervised!(
        {Jido.Chat.Sensor,
         client: c,
         source: Source,
         emit: "jido.chat.message.received",
         interval: 60_000,
         dispatch: {:pid, target: self()}}
      )

    send(pid, :poll)
    assert_receive {:signal, %{type: "jido.chat.message.received"}}, 2_000
    assert :sys.get_state(pid).cursor == 11

    assert {:error, {:already_started, ^pid}} =
             Jido.Chat.Sensor.start_link(
               client: c,
               source: Source,
               emit: "jido.chat.**",
               dispatch: {:pid, target: self()}
             )
  end
end
