defmodule Jido.Chat.Runtime.Storage.Commit do
  @moduledoc "Optional atomic batch capability for one storage adapter."

  @type command ::
          {:append_message, Jido.Chat.Message.t()}
          | {:put_link, map()}
          | {:put_work, map()}
          | {:update_work, String.t(), Jido.Chat.Runtime.Storage.Outbox.status(), map()}
          | {:put_room, map()}
          | {:put_members, String.t(), [term()]}

  @callback commit(resource :: term(), [command()]) :: {:ok, [term()]} | {:error, term()}
end
