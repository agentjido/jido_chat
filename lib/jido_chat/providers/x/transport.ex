defmodule Jido.Chat.X.Transport do
  @moduledoc "Transport contract for X Direct Message API calls."

  @callback send_dm(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback send_conversation_message(String.t(), String.t(), keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback delete_dm_event(String.t(), keyword()) :: :ok | {:error, term()}
  @callback fetch_dm_event(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback fetch_conversation_messages(String.t(), keyword()) ::
              {:ok, list(map()) | map()} | {:error, term()}
end
