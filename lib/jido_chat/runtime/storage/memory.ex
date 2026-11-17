defmodule Jido.Chat.Runtime.Storage.Memory do
  @moduledoc """
  Process-explicit in-memory implementation of all Runtime storage capabilities.

  The host starts and supervises this process. Data survives callers and account
  Agent restarts, but it does not survive this process or VM restart.
  """

  use GenServer

  alias Jido.Chat.Runtime.Storage

  alias Jido.Chat.Runtime.Storage.{
    Bindings,
    Commit,
    Connections,
    Engine,
    History,
    Links,
    Memberships,
    Outbox,
    Reactions,
    RoomDeclarations,
    Rooms
  }

  use Storage.Adapter,
    capabilities: [
      Links,
      Outbox,
      Reactions,
      Rooms,
      RoomDeclarations,
      Memberships,
      History,
      Connections,
      Bindings,
      Commit
    ]

  @doc "Starts an empty memory storage resource."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.take(opts, [:name]))
  end

  @impl Links
  def put_link(server, link), do: GenServer.call(server, {:command, {:put_link, link}})

  @impl Links
  def link_for_local(server, account_id, local_message_id),
    do: GenServer.call(server, {:query, {:link_for_local, account_id, local_message_id}})

  @impl Links
  def links_for_local(server, account_id, local_message_id),
    do: GenServer.call(server, {:query, {:links_for_local, account_id, local_message_id}})

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
  def insert_room(server, record),
    do: GenServer.call(server, {:command, {:insert_room, record}})

  @impl Rooms
  def get_room(server, id), do: GenServer.call(server, {:query, {:get_room, id}})

  @impl Rooms
  def list_rooms(server, opts \\ []),
    do: GenServer.call(server, {:query, {:list_rooms, opts}})

  @impl Rooms
  def update_room(server, id, expected_revision, record),
    do: GenServer.call(server, {:command, {:update_room, id, expected_revision, record}})

  @impl Rooms
  def delete_room(server, id, expected_revision),
    do: GenServer.call(server, {:command, {:delete_room, id, expected_revision}})

  @impl RoomDeclarations
  def insert_room_declaration(server, value),
    do: GenServer.call(server, {:command, {:insert_room_declaration, value}})

  @impl RoomDeclarations
  def get_room_declaration(server, id),
    do: GenServer.call(server, {:query, {:get_room_declaration, id}})

  @impl RoomDeclarations
  def list_room_declarations(server),
    do: GenServer.call(server, {:query, :list_room_declarations})

  @impl RoomDeclarations
  def update_room_declaration(server, id, revision, value),
    do: GenServer.call(server, {:command, {:update_room_declaration, id, revision, value}})

  @impl RoomDeclarations
  def delete_room_declaration(server, id, revision),
    do: GenServer.call(server, {:command, {:delete_room_declaration, id, revision}})

  @impl Memberships
  def insert_membership(server, value),
    do: GenServer.call(server, {:command, {:insert_membership, value}})

  @impl Memberships
  def get_membership(server, room_id, member_key),
    do: GenServer.call(server, {:query, {:get_membership, room_id, member_key}})

  @impl Memberships
  def list_memberships(server, room_id, opts \\ []),
    do: GenServer.call(server, {:query, {:list_memberships, room_id, opts}})

  @impl Memberships
  def update_membership(server, room_id, member_key, revision, value),
    do: GenServer.call(server, {:command, {:update_membership, room_id, member_key, revision, value}})

  @impl History
  def insert_history(server, value),
    do: GenServer.call(server, {:command, {:insert_history, value}})

  @impl History
  def get_history(server, room_id, message_id),
    do: GenServer.call(server, {:query, {:get_history, room_id, message_id}})

  @impl History
  def list_history(server, room_id, opts \\ []),
    do: GenServer.call(server, {:query, {:list_history, room_id, opts}})

  @impl History
  def last_history_sequence(server, room_id),
    do: GenServer.call(server, {:query, {:last_history_sequence, room_id}})

  @impl Reactions
  def insert_reaction(server, reaction),
    do: GenServer.call(server, {:command, {:insert_reaction, reaction}})

  @impl Reactions
  def get_reaction(server, room_id, message_id, reaction, actor_key),
    do: GenServer.call(server, {:query, {:get_reaction, room_id, message_id, reaction, actor_key}})

  @impl Reactions
  def list_reactions(server, room_id, opts \\ []),
    do: GenServer.call(server, {:query, {:list_reactions, room_id, opts}})

  @impl Reactions
  def update_reaction(server, room_id, message_id, reaction, actor_key, revision, value),
    do:
      GenServer.call(
        server,
        {:command, {:update_reaction, room_id, message_id, reaction, actor_key, revision, value}}
      )

  @impl Connections
  def insert_connection(server, declaration),
    do: GenServer.call(server, {:command, {:insert_connection, declaration}})

  @impl Connections
  def get_connection(server, account_id),
    do: GenServer.call(server, {:query, {:get_connection, account_id}})

  @impl Connections
  def list_connections(server), do: GenServer.call(server, {:query, :list_connections})

  @impl Connections
  def update_connection(server, account_id, revision, declaration),
    do:
      GenServer.call(
        server,
        {:command, {:update_connection, account_id, revision, declaration}}
      )

  @impl Bindings
  def insert_binding(server, binding),
    do: GenServer.call(server, {:command, {:insert_binding, binding}})

  @impl Bindings
  def get_binding(server, account_id, external_room_id),
    do: GenServer.call(server, {:query, {:get_binding, account_id, external_room_id}})

  @impl Bindings
  def list_bindings(server, account_id, opts \\ []),
    do: GenServer.call(server, {:query, {:list_bindings, account_id, opts}})

  @impl Bindings
  def update_binding(server, account_id, external_room_id, revision, binding),
    do:
      GenServer.call(
        server,
        {:command, {:update_binding, account_id, external_room_id, revision, binding}}
      )

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
