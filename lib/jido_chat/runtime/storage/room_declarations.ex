defmodule Jido.Chat.Runtime.Storage.RoomDeclarations do
  @moduledoc "Storage capability for durable managed Room declarations."

  alias Jido.Chat.Runtime.Room.Declaration

  @callback insert_room_declaration(term(), Declaration.t()) ::
              {:ok, Declaration.t()} | {:error, term()}
  @callback get_room_declaration(term(), String.t()) ::
              {:ok, Declaration.t() | nil} | {:error, term()}
  @callback list_room_declarations(term()) :: {:ok, [Declaration.t()]} | {:error, term()}
  @callback update_room_declaration(term(), String.t(), pos_integer(), Declaration.t()) ::
              {:ok, Declaration.t()} | {:error, term()}
  @callback delete_room_declaration(term(), String.t(), pos_integer()) ::
              {:ok, :ok} | {:error, term()}
end
