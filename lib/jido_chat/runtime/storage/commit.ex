defmodule Jido.Chat.Runtime.Storage.Commit do
  @moduledoc "Optional atomic batch capability for one storage adapter."

  @type command ::
          {:put_link, map()}
          | {:put_work, map()}
          | {:update_work, String.t(), Jido.Chat.Runtime.Storage.Outbox.status(), map()}
          | {:insert_room, Jido.Chat.Runtime.Room.Record.t()}
          | {:update_room, String.t(), pos_integer(), Jido.Chat.Runtime.Room.Record.t()}
          | {:delete_room, String.t(), pos_integer()}
          | {:insert_room_declaration, Jido.Chat.Runtime.Room.Declaration.t()}
          | {:update_room_declaration, String.t(), pos_integer(), Jido.Chat.Runtime.Room.Declaration.t()}
          | {:delete_room_declaration, String.t(), pos_integer()}
          | {:insert_membership, Jido.Chat.Runtime.Room.Membership.t()}
          | {:update_membership, String.t(), String.t(), pos_integer(), Jido.Chat.Runtime.Room.Membership.t()}
          | {:insert_history, Jido.Chat.Runtime.Room.HistoryRecord.t()}
          | {:insert_reaction, Jido.Chat.Runtime.Room.Reaction.t()}
          | {:update_reaction, String.t(), String.t(), String.t(), String.t(), pos_integer(),
             Jido.Chat.Runtime.Room.Reaction.t()}
          | {:insert_connection, Jido.Chat.Runtime.Connection.Declaration.t()}
          | {:update_connection, String.t(), pos_integer(), Jido.Chat.Runtime.Connection.Declaration.t()}
          | {:insert_binding, Jido.Chat.Runtime.Bridge.Binding.t()}
          | {:update_binding, String.t(), String.t(), pos_integer(), Jido.Chat.Runtime.Bridge.Binding.t()}

  @callback commit(resource :: term(), [command()]) :: {:ok, [term()]} | {:error, term()}
end
