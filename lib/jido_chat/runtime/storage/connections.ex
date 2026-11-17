defmodule Jido.Chat.Runtime.Storage.Connections do
  @moduledoc "Storage capability for durable provider account declarations."

  alias Jido.Chat.Runtime.Connection.Declaration

  @callback insert_connection(term(), Declaration.t()) ::
              {:ok, Declaration.t()} | {:error, term()}
  @callback get_connection(term(), String.t()) ::
              {:ok, Declaration.t() | nil} | {:error, term()}
  @callback list_connections(term()) :: {:ok, [Declaration.t()]} | {:error, term()}
  @callback update_connection(term(), String.t(), pos_integer(), Declaration.t()) ::
              {:ok, Declaration.t()} | {:error, term()}
end
