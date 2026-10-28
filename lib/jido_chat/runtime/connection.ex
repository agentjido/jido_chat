defmodule Jido.Chat.Runtime.Connection do
  @moduledoc """
  Activates provider account Agents through a Runtime facade and host-owned Jido.

  Runtime adds no connection supervisor. Jido owns Agent activation, restart,
  and shutdown.
  """

  alias Jido.Chat.Runtime.Bridge

  @max_account_id_bytes 256

  @doc "Starts one account Agent and returns its stable Ref and AgentServer PID."
  @spec start(module(), String.t(), module() | Jido.Agent.t()) ::
          {:ok, Jido.Agent.Ref.t(), pid()} | {:error, term()}
  def start(instance, account_id, definition) do
    with :ok <- available(instance),
         :ok <- valid_account_id(account_id),
         {:ok, ref} <- ref(instance, account_id),
         {:ok, agent} <- Jido.Agent.instantiate(definition, id: ref.id),
         :ok <- one_connection(agent),
         {:ok, agent} <- bind_bridge(agent, instance, account_id, ref),
         {:error, :not_found} <- Jido.resolve_agent(instance.jido(), ref),
         {:ok, server} <- Jido.start_agent_ref(instance.jido(), ref, agent),
         :ok <- Jido.AgentServer.await_ready(server),
         :ok <- recover_bridge(agent, instance, account_id) do
      {:ok, ref, server}
    else
      {:ok, server} when is_pid(server) -> {:error, {:already_started, server}}
      {:error, _} = error -> error
      other -> {:error, other}
    end
  catch
    :exit, _ -> {:error, :jido_unavailable}
  end

  @doc "Stops one provider account through the host Jido instance."
  @spec stop(module(), String.t()) :: :ok | {:error, term()}
  def stop(instance, account_id) do
    with :ok <- available(instance),
         {:ok, ref} <- ref(instance, account_id),
         {:ok, _server} <- Jido.resolve_agent(instance.jido(), ref) do
      Jido.stop_agent_ref(instance.jido(), ref)
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, _} = error -> error
    end
  catch
    :exit, _ -> {:error, :jido_unavailable}
  end

  @doc "Returns safe local status for one provider account."
  @spec status(module(), String.t()) :: {:ok, map()} | {:error, term()}
  def status(instance, account_id) do
    with :ok <- available(instance),
         {:ok, ref} <- ref(instance, account_id),
         {:ok, server} <- Jido.resolve_agent(instance.jido(), ref) do
      {:ok, %{account_id: account_id, ref: ref, chat: Jido.Chat.Plugin.status(server)}}
    end
  catch
    :exit, _ -> {:error, :jido_unavailable}
  end

  @doc "Returns the stable Agent Ref selected for one account."
  @spec ref(module(), String.t()) :: {:ok, Jido.Agent.Ref.t()} | {:error, term()}
  def ref(instance, account_id) do
    with :ok <- available(instance),
         :ok <- valid_account_id(account_id) do
      id = "jido.chat/account/" <> Base.url_encode64(account_id, padding: false)
      Jido.agent_ref(instance.jido(), id)
    end
  catch
    :exit, _ -> {:error, :jido_unavailable}
  end

  defp one_connection(agent) do
    case Enum.filter(agent.extensions, &(&1.provider == Jido.Chat.Plugin)) do
      [%{data: %{connections: [_connection]}}] -> :ok
      _ -> {:error, :one_chat_connection_required}
    end
  end

  defp bind_bridge(agent, instance, account_id, ref) do
    bridge? = Enum.any?(agent.extensions, &(&1.provider == Bridge))

    if bridge? and is_nil(instance.storage()) do
      {:error, :bridge_storage_required}
    else
      bind_bridge_options(agent, instance, account_id, ref)
    end
  end

  defp recover_bridge(agent, instance, account_id) do
    if Enum.any?(agent.extensions, &(&1.provider == Bridge)),
      do: Bridge.recover(instance, account_id),
      else: :ok
  end

  defp bind_bridge_options(agent, instance, account_id, ref) do
    [connection] = Enum.filter(agent.extensions, &(&1.provider == Jido.Chat.Plugin))
    [chat] = connection.data.connections
    {work_limit, queue_limit} = instance.provider_work_limits()

    extensions =
      Enum.map(agent.extensions, fn
        %{provider: Bridge} = extension ->
          data =
            Map.merge(extension.data, %{
              runtime: instance,
              storage: instance.storage(),
              account_id: account_id,
              account_ref: ref,
              client_id: chat.client.id,
              client_source: Jido.Chat.Signal.Identity.client_source(chat.client.id),
              provider_work_limit: work_limit,
              provider_queue_limit: queue_limit
            })

          %{extension | data: data}

        extension ->
          extension
      end)

    {:ok, %{agent | extensions: extensions}}
  end

  defp available(instance) when is_atom(instance) do
    cond do
      not function_exported?(instance, :jido, 0) -> {:error, :invalid_runtime}
      not function_exported?(instance, :storage, 0) -> {:error, :invalid_runtime}
      not is_pid(Process.whereis(instance.jido())) -> {:error, :jido_unavailable}
      true -> :ok
    end
  end

  defp available(_), do: {:error, :invalid_runtime}

  defp valid_account_id(value)
       when is_binary(value) and byte_size(value) in 1..@max_account_id_bytes,
       do: :ok

  defp valid_account_id(_), do: {:error, :invalid_account_id}
end
