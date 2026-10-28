defmodule Jido.Chat.Runtime.Storage.Links do
  @moduledoc "Storage capability for stable local and provider message links."

  @type link :: %{
          required(:account_id) => String.t(),
          required(:local_message_id) => String.t(),
          required(:external_room_id) => String.t(),
          required(:external_message_id) => String.t(),
          optional(atom()) => term()
        }

  @callback put_link(resource :: term(), link()) :: {:ok, link()} | {:error, term()}
  @callback link_for_local(resource :: term(), account_id :: String.t(), local_message_id :: String.t()) ::
              {:ok, link() | nil} | {:error, term()}
  @callback link_for_external(
              resource :: term(),
              account_id :: String.t(),
              external_room_id :: String.t(),
              external_message_id :: String.t()
            ) :: {:ok, link() | nil} | {:error, term()}
end
