defmodule Jido.Chat.Runtime.Storage.Commit do
  @moduledoc "Optional atomic batch capability for one storage adapter."

  @type command ::
          {:put_link, map()}
          | {:put_work, map()}
          | {:update_work, String.t(), Jido.Chat.Runtime.Storage.Outbox.status(), map()}
          | {:insert_room, Jido.Chat.Runtime.Room.Record.t()}
          | {:update_room, String.t(), pos_integer(), Jido.Chat.Runtime.Room.Record.t()}
          | {:delete_room, String.t(), pos_integer()}

  @callback commit(resource :: term(), [command()]) :: {:ok, [term()]} | {:error, term()}
end
