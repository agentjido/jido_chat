defmodule Jido.Chat.Runtime.Storage.History do
  @moduledoc "Storage capability for ordered normalized room messages."

  @callback append_message(resource :: term(), Jido.Chat.Message.t()) ::
              {:ok, Jido.Chat.Message.t()} | {:error, term()}
  @callback list_messages(resource :: term(), room_id :: String.t(), keyword()) ::
              {:ok, [Jido.Chat.Message.t()]} | {:error, term()}
end
