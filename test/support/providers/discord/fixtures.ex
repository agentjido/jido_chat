defmodule Jido.Chat.Discord.TestTransport do
  @moduledoc false
  @behaviour Jido.Chat.Discord.Transport
  @doc false
  def call(token, method, path, body, opts) do
    if observer = opts[:transport_observer], do: send(observer, {:discord_transport_options, opts})
    opts[:handler].(token, method, path, body)
  end
end

defmodule Jido.Chat.Discord.TestGateway do
  @moduledoc false
  @doc false
  def open(url, opts) do
    test = opts[:test_pid]
    worker = self()

    pid =
      spawn_link(fn ->
        Process.flag(:trap_exit, true)
        loop(test)
      end)

    send(test, {:gateway_open, worker, pid, url})
    {:ok, pid}
  end

  defp loop(test) do
    receive do
      {:frame, data} ->
        send(test, {:gateway_sent, data})
        loop(test)

      :close ->
        send(test, {:gateway_closed, self()})
    end
  end

  @doc false
  def upgrade(pid), do: pid
  @doc false
  def send_frame(pid, _, data), do: send(pid, {:frame, data})
  @doc false
  def close(pid), do: send(pid, :close)
end

defmodule Jido.Chat.Discord.Fixtures do
  @moduledoc false
  @doc false
  def client(handler \\ fn _, _, _, _ -> {:ok, %{}} end, opts \\ []) do
    Jido.Chat.Client.new!(Jido.Chat.Discord.Adapter,
      id: Keyword.get(opts, :id, "discord-test"),
      credentials: %{token: Keyword.get(opts, :token, "test-secret")},
      transport: Jido.Chat.Discord.TestTransport,
      config: Keyword.merge([handler: handler, bot_id: "bot"], Keyword.get(opts, :config, []))
    )
  end

  @doc false
  def interaction(client, room, id) do
    %Jido.Chat.Discord.Interaction{
      client_id: client.id,
      bot_id: client.config[:bot_id] || "bot",
      room_id: room,
      interaction_id: id,
      token: Base.encode64(:crypto.strong_rand_bytes(24)),
      received_at: System.monotonic_time(:millisecond)
    }
  end

  @doc false
  def message(overrides \\ %{}),
    do:
      Map.merge(
        %{
          "id" => "101",
          "channel_id" => "202",
          "guild_id" => "303",
          "content" => "hello",
          "author" => %{"id" => "404", "username" => "human"}
        },
        overrides
      )

  @doc false
  def request(definition, data),
    do:
      Jido.Chat.Signal.Policy.new!(
        definition,
        Map.merge(%{"client_id" => "discord-test", "request_id" => Jido.Id.uuid7()}, data)
      )
end

defmodule Jido.Chat.Discord.TestHTTP do
  @moduledoc false
  @doc false
  def run(request), do: request.options[:finch_private][:discord_test_handler].(request)
end
