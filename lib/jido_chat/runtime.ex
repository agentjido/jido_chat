defmodule Jido.Chat.Runtime do
  @moduledoc """
  Optional stateful chat services built on a host-owned Jido instance.

  Runtime owns rooms, participants, provider account activation, bridges,
  bounded provider work, and small storage capability contracts. Starting the
  `:jido_chat` application does not start Runtime.
  """

  use Boundary,
    deps: [Jido.Chat],
    exports: [Room, Participant, Connection, Bridge, {Actions, []}, {Signal, []}, {Storage, []}]

  @doc "Defines one process-free Runtime facade over a host-owned Jido instance."
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      opts =
        Keyword.validate!(opts, [
          :jido,
          :storage,
          :provider_work_limit,
          :provider_queue_limit
        ])

      @chat_runtime_jido Keyword.fetch!(opts, :jido)
      @chat_runtime_storage Keyword.get(opts, :storage)
      @chat_runtime_provider_work_limit Keyword.get(opts, :provider_work_limit, 4)
      @chat_runtime_provider_queue_limit Keyword.get(opts, :provider_queue_limit, 1_000)

      unless is_atom(@chat_runtime_jido) and @chat_runtime_jido not in [nil, true, false] do
        raise ArgumentError, "jido must be a named host Jido instance"
      end

      unless is_nil(@chat_runtime_storage) or
               match?({adapter, _resource} when is_atom(adapter), @chat_runtime_storage) do
        raise ArgumentError, "storage must be {adapter, resource}"
      end

      unless is_integer(@chat_runtime_provider_work_limit) and
               @chat_runtime_provider_work_limit > 0 do
        raise ArgumentError, "provider_work_limit must be a positive integer"
      end

      unless is_integer(@chat_runtime_provider_queue_limit) and
               @chat_runtime_provider_queue_limit > 0 do
        raise ArgumentError, "provider_queue_limit must be a positive integer"
      end

      @doc "Returns the required host-owned Jido instance."
      @spec jido() :: atom()
      def jido, do: @chat_runtime_jido

      @doc "Returns the selected Runtime storage resource, when configured."
      @spec storage() :: Jido.Chat.Runtime.Storage.selection() | nil
      def storage, do: @chat_runtime_storage

      @doc false
      def provider_work_limits do
        {@chat_runtime_provider_work_limit, @chat_runtime_provider_queue_limit}
      end

      @doc "Returns the stable Agent Ref for one provider account."
      def connection_ref(account_id),
        do: Jido.Chat.Runtime.Connection.ref(__MODULE__, account_id)

      @doc "Starts one provider account through the host Jido instance."
      def start_connection(account_id, definition),
        do: Jido.Chat.Runtime.Connection.start(__MODULE__, account_id, definition)

      @doc "Stops one provider account through the host Jido instance."
      def stop_connection(account_id),
        do: Jido.Chat.Runtime.Connection.stop(__MODULE__, account_id)

      @doc "Returns safe local status for one provider account."
      def connection_status(account_id),
        do: Jido.Chat.Runtime.Connection.status(__MODULE__, account_id)

      @doc "Returns stored Bridge provider-work status for one account."
      def bridge_status(account_id),
        do: Jido.Chat.Runtime.Bridge.status(__MODULE__, account_id)

      @doc "Schedules pending Bridge work for one active account."
      def recover_bridge(account_id),
        do: Jido.Chat.Runtime.Bridge.recover(__MODULE__, account_id)

      @doc "Returns the Bridge link for one local message."
      def bridge_link(account_id, local_message_id),
        do: Jido.Chat.Runtime.Bridge.link(__MODULE__, account_id, local_message_id)
    end
  end
end
