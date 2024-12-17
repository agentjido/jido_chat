defmodule JidoChat do
  @moduledoc """
  JidoChat is a structured chat room system supporting human and agent participants
  with customizable turn-taking strategies and persistence.

  ## Features

  - Multiple persistence adapters (ETS, Agent-based memory store)
  - Flexible turn-taking strategies
  - Support for human and AI agent participants
  - Message history management
  - Conversation context extraction for LLMs
  """

  alias JidoChat.{Room, Participant, Message, Conversation}

  @type room_id :: String.t()
  @type participant_id :: String.t()
  @type error :: {:error, term()}

  @doc """
  Creates a new chat room with the specified options.

  ## Options

    * `:strategy` - The turn-taking strategy module (default: Strategy.FreeForm)
    * `:message_limit` - Maximum number of messages to retain (default: 1000)
    * `:persistence` - Persistence adapter to use (default: Persistence.ETS)
    * `:name` - Room name (default: generated from room_id)

  ## Examples

      iex> {:ok, pid} = JidoChat.create_room("room-123", strategy: JidoChat.Room.Strategy.RoundRobin)
      {:ok, pid}
  """
  @spec create_room(room_id(), keyword()) :: {:ok, pid()} | error()
  def create_room(room_id, opts \\ []) do
    Room.start_link(room_id, opts)
  end

  @doc """
  Adds a participant to a room.

  ## Examples

      iex> {:ok, room_pid} = JidoChat.create_room("room-123")
      iex> participant = %JidoChat.Participant{id: "user1", name: "Alice", type: :human}
      iex> JidoChat.join_room(room_pid, participant)
      :ok
  """
  @spec join_room(pid(), Participant.t()) :: :ok | error()
  def join_room(room_pid, participant) do
    Room.join(room_pid, participant)
  end

  @doc """
  Posts a message to a room.

  ## Examples

    iex> {:ok, room_pid} = JidoChat.create_room("room-123")
    iex> JidoChat.post_message(room_pid, "user1", "Hello!")
    {:ok, %JidoChat.Message{}}
  """
  @spec post_message(pid(), participant_id(), String.t()) :: {:ok, Message.t()} | error()
  def post_message(room_pid, participant_id, content) do
    Room.post_message(room_pid, participant_id, content)
  end

  @doc """
  Creates a conversation context from recent messages suitable for LLM processing.

  ## Options

    * `:message_limit` - Maximum number of messages to include (default: 10)
    * `:include_metadata` - Whether to include message metadata (default: false)
    * `:format` - Conversation format (:chat_ml | :anthropic | :raw) (default: :chat_ml)

  ## Examples

    iex> {:ok, room_pid} = JidoChat.create_room("room-123")
    iex> JidoChat.get_conversation_context(room_pid, limit: 5)
    {:ok, %JidoChat.Conversation{}}
  """
  @spec get_conversation_context(pid(), keyword()) :: {:ok, Conversation.t()} | error()
  def get_conversation_context(room_pid, opts \\ []) do
    with {:ok, messages} <- Room.get_messages(room_pid),
         {:ok, participants} <- Room.get_participants(room_pid) do
      Conversation.from_messages(messages, participants, opts)
    end
  end
end