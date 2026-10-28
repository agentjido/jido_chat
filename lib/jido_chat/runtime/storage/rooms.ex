defmodule Jido.Chat.Runtime.Storage.Rooms do
  @moduledoc "Optional storage capability for room definitions and membership."

  @type room :: %{required(:id) => String.t(), optional(atom()) => term()}

  @callback put_room(resource :: term(), room()) :: {:ok, room()} | {:error, term()}
  @callback get_room(resource :: term(), id :: String.t()) :: {:ok, room() | nil} | {:error, term()}
  @callback put_members(resource :: term(), id :: String.t(), [term()]) ::
              {:ok, [term()]} | {:error, term()}
  @callback get_members(resource :: term(), id :: String.t()) :: {:ok, [term()]} | {:error, term()}
end
