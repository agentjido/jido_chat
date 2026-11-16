defmodule Jido.Chat.Runtime.Storage.History do
  @moduledoc """
  Storage capability for immutable durable Room message history.

  List results are oldest first. `:before` and `:after` are exclusive message-ID
  cursors. `:thread_id` filters a thread. `:latest` selects the newest bounded
  page while keeping its result in oldest-first order. Limits are 1 through
  1,000.
  """

  alias Jido.Chat.Runtime.Room.HistoryRecord

  @callback insert_history(term(), HistoryRecord.t()) ::
              {:ok, HistoryRecord.t()} | {:error, term()}
  @callback get_history(term(), String.t(), String.t()) ::
              {:ok, HistoryRecord.t() | nil} | {:error, term()}
  @callback list_history(term(), String.t(), keyword()) ::
              {:ok, [HistoryRecord.t()]} | {:error, term()}
  @callback last_history_sequence(term(), String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
end
