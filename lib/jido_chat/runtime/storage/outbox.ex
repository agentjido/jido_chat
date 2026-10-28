defmodule Jido.Chat.Runtime.Storage.Outbox do
  @moduledoc "Storage capability for recoverable provider delivery intent."

  @statuses [:pending, :claimed, :submitted, :completed, :failed, :unknown]
  @terminal [:completed, :failed, :unknown]

  @type status :: :pending | :claimed | :submitted | :completed | :failed | :unknown
  @type work :: %{
          required(:id) => String.t(),
          required(:account_id) => String.t(),
          required(:status) => status(),
          optional(atom()) => term()
        }

  @callback put_work(resource :: term(), work()) :: {:ok, work()} | {:error, term()}
  @callback get_work(resource :: term(), id :: String.t()) :: {:ok, work() | nil} | {:error, term()}
  @callback list_work(resource :: term(), account_id :: String.t(), keyword()) ::
              {:ok, [work()]} | {:error, term()}
  @callback update_work(resource :: term(), id :: String.t(), status(), map()) ::
              {:ok, work()} | {:error, term()}

  @doc "Returns all supported Outbox states."
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc "Returns true for an allowed state transition."
  @spec valid_transition?(status(), status()) :: boolean()
  def valid_transition?(status, status), do: status in @statuses
  def valid_transition?(:pending, :claimed), do: true
  def valid_transition?(:claimed, next), do: next in [:pending, :submitted]
  def valid_transition?(:submitted, next), do: next in @terminal
  def valid_transition?(_, _), do: false
end
