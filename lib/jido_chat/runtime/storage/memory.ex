defmodule Jido.Chat.Runtime.Storage.Memory do
  @moduledoc """
  Process-explicit in-memory implementation of all Runtime storage capabilities.

  The host starts and supervises this process. Data survives callers and account
  Agent restarts, but it does not survive this process or VM restart.
  """

  use GenServer

  alias Jido.Chat.Message
  alias Jido.Chat.Runtime.Storage
  alias Jido.Chat.Runtime.Storage.{Commit, Engine, History, Links, Outbox, Rooms}

  use Storage.Adapter,
    capabilities: [History, Links, Outbox, Rooms, Commit]

  @doc "Starts an empty memory storage resource."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.take(opts, [:name]))
  end

  @impl History
  def append_message(server, %Message{} = message),
    do: GenServer.call(server, {:command, {:append_message, message}})

  @impl History
  def list_messages(server, room_id, opts \\ []),
    do: GenServer.call(server, {:query, {:list_messages, room_id, opts}})

  @impl Links
  def put_link(server, link), do: GenServer.call(server, {:command, {:put_link, link}})

  @impl Links
  def link_for_local(server, account_id, local_message_id),
    do: GenServer.call(server, {:query, {:link_for_local, account_id, local_message_id}})

  @impl Links
  def link_for_external(server, account_id, external_room_id, external_message_id),
    do: GenServer.call(server, {:query, {:link_for_external, account_id, external_room_id, external_message_id}})

  @impl Outbox
  def put_work(server, work), do: GenServer.call(server, {:command, {:put_work, work}})

  @impl Outbox
  def get_work(server, id), do: GenServer.call(server, {:query, {:get_work, id}})

  @impl Outbox
  def list_work(server, account_id, opts \\ []),
    do: GenServer.call(server, {:query, {:list_work, account_id, opts}})

  @impl Outbox
  def update_work(server, id, expected_status, changes),
    do: GenServer.call(server, {:command, {:update_work, id, expected_status, changes}})

  @impl Rooms
  def put_room(server, room), do: GenServer.call(server, {:command, {:put_room, room}})

  @impl Rooms
  def get_room(server, id), do: GenServer.call(server, {:query, {:get_room, id}})

  @impl Rooms
  def put_members(server, id, members),
    do: GenServer.call(server, {:command, {:put_members, id, members}})

  @impl Rooms
  def get_members(server, id), do: GenServer.call(server, {:query, {:get_members, id}})

  @impl Commit
  def commit(server, commands) when is_list(commands),
    do: GenServer.call(server, {:commit, commands})

  @impl true
  def init(:ok), do: {:ok, Engine.new()}

  @impl true
  def handle_call({:command, command}, _from, state) do
    case Engine.command(state, command) do
      {:ok, result, next} -> {:reply, {:ok, result}, next}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:commit, commands}, _from, state) do
    case Engine.commit(state, commands) do
      {:ok, results, next} -> {:reply, {:ok, results}, next}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:query, query}, _from, state),
    do: {:reply, Engine.query(state, query), state}
end
