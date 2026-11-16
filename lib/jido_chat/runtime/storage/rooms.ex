defmodule Jido.Chat.Runtime.Storage.Rooms do
  @moduledoc """
  Storage capability for durable Room records and deterministic queries.

  List results use ascending `{inserted_at, id}` order. `:after` is an
  exclusive Room-ID cursor. The supported query options are `:kind`, `:after`,
  and `:limit`.
  """

  alias Jido.Chat.Runtime.Room.Record

  @type query_option ::
          {:kind, Record.kind()}
          | {:after, String.t()}
          | {:limit, pos_integer()}

  @callback insert_room(resource :: term(), Record.t()) ::
              {:ok, Record.t()} | {:error, term()}
  @callback get_room(resource :: term(), id :: String.t()) ::
              {:ok, Record.t() | nil} | {:error, term()}
  @callback list_rooms(resource :: term(), [query_option()]) ::
              {:ok, [Record.t()]} | {:error, term()}
  @callback update_room(resource :: term(), String.t(), pos_integer(), Record.t()) ::
              {:ok, Record.t()} | {:error, term()}
  @callback delete_room(resource :: term(), String.t(), pos_integer()) ::
              {:ok, :ok} | {:error, term()}
end
