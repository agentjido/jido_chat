defmodule Jido.Chat.Runtime.Storage.Commit do
  @moduledoc "Optional atomic batch capability for one storage adapter."

  @type command ::
          {:put_link, map()}
          | {:put_work, map()}
          | {:update_work, String.t(), Jido.Chat.Runtime.Storage.Outbox.status(), map()}

  @callback commit(resource :: term(), [command()]) :: {:ok, [term()]} | {:error, term()}
end
