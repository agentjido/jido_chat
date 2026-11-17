defmodule Jido.Chat.Runtime.Connection do
  @moduledoc """
  Activates provider account Agents through a Runtime facade and host-owned Jido.

  Runtime adds no connection supervisor. Jido owns Agent activation, restart,
  and shutdown. Durable declarations contain secret references only. A host
  resolver provides credentials when Runtime starts the Agent.
  """

  alias Jido.Chat.Runtime.Bridge
  alias Jido.Chat.Runtime.Bridge.Binding
  alias Jido.Chat.Runtime.Connection.Declaration
  alias Jido.Chat.Runtime.{Room, SecretResolver}

  @max_account_id_bytes 256

  @doc "Starts one account Agent and returns its stable Ref and AgentServer PID."
  @spec start(module(), String.t(), module() | Jido.Agent.t()) ::
          {:ok, Jido.Agent.Address.t(), pid()} | {:error, term()}
  def start(instance, account_id, definition) do
    with {:ok, ref, agent} <- prepare(instance, account_id, definition),
         do: start_prepared(instance, account_id, ref, agent)
  end

  @doc false
  @spec prepare(module(), String.t(), module() | Jido.Agent.t(), keyword()) ::
          {:ok, Jido.Agent.Address.t(), Jido.Agent.t()} | {:error, term()}
  def prepare(instance, account_id, definition, opts \\ []) do
    declaration = Keyword.get(opts, :declaration)
    bindings = Keyword.get(opts, :bindings)

    with :ok <- available(instance),
         :ok <- valid_account_id(account_id),
         {:ok, ref} <- ref(instance, account_id),
         {:ok, agent} <- Jido.Agent.instantiate(definition, id: ref.id),
         :ok <- one_connection(agent),
         {:ok, agent} <- materialize(agent, instance, account_id, declaration, bindings),
         {:ok, agent} <- bind_bridge(agent, instance, account_id, ref, bindings),
         do: {:ok, ref, agent}
  catch
    :exit, _reason -> {:error, :jido_unavailable}
  end

  @doc false
  @spec expected(
          module(),
          String.t(),
          module() | Jido.Agent.t(),
          Declaration.t() | nil,
          [Binding.t()] | nil
        ) :: {:ok, Jido.Agent.Address.t(), Jido.Agent.t()} | {:error, term()}
  def expected(instance, account_id, definition, declaration, bindings) do
    with :ok <- available(instance),
         {:ok, ref} <- ref(instance, account_id),
         {:ok, agent} <- Jido.Agent.instantiate(definition, id: ref.id),
         :ok <- one_connection(agent) do
      {:ok, ref, put_configuration(agent, configuration_key(declaration, bindings))}
    end
  catch
    :exit, _reason -> {:error, :jido_unavailable}
  end

  @doc false
  @spec start_prepared(module(), String.t(), Jido.Agent.Address.t(), Jido.Agent.t()) ::
          {:ok, Jido.Agent.Address.t(), pid()} | {:error, term()}
  def start_prepared(instance, account_id, ref, agent) do
    case Jido.resolve_agent(instance.jido(), ref) do
      {:error, :not_found} -> start_ready(instance, account_id, agent, ref)
      {:ok, server} when is_pid(server) -> {:error, {:already_started, server}}
      {:error, _reason} = error -> error
    end
  catch
    :exit, _reason -> {:error, :jido_unavailable}
  end

  @doc false
  @spec validate_definition(module() | Jido.Agent.t()) :: :ok | {:error, term()}
  def validate_definition(definition) do
    with {:ok, agent} <- Jido.Agent.instantiate(definition, id: "jido.chat/definition-check"),
         do: one_connection(agent)
  end

  @doc false
  def same_configuration?(expected, actual) do
    Room.same_definition?(expected, actual) and
      configuration_marker(expected) == configuration_marker(actual)
  end

  defp start_ready(instance, account_id, agent, ref) do
    case Jido.start_agent(instance.jido(), agent, partition: ref.partition) do
      {:ok, server} ->
        try do
          with :ok <- Jido.AgentServer.await_ready(server),
               :ok <- recover_bridge(agent, instance, account_id) do
            {:ok, ref, server}
          else
            {:error, _reason} = error ->
              stop_failed_start(instance, ref, server)
              error
          end
        catch
          :exit, _reason ->
            stop_failed_start(instance, ref, server)
            {:error, :jido_unavailable}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp stop_failed_start(instance, ref, server) do
    _ = Jido.stop_agent(instance.jido(), server, partition: ref.partition)
    :ok
  catch
    :exit, _reason -> :ok
  end

  @doc "Stops one provider account through the host Jido instance."
  @spec stop(module(), String.t()) :: :ok | {:error, term()}
  def stop(instance, account_id) do
    with :ok <- available(instance),
         {:ok, ref} <- ref(instance, account_id),
         {:ok, _server} <- Jido.resolve_agent(instance.jido(), ref) do
      Room.stop_agent(instance.jido(), ref)
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  catch
    :exit, _reason -> {:error, :jido_unavailable}
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
    :exit, _reason -> {:error, :jido_unavailable}
  end

  @doc "Returns the stable Agent Address selected for one account."
  @spec ref(module(), String.t()) :: {:ok, Jido.Agent.Address.t()} | {:error, term()}
  def ref(instance, account_id) do
    with :ok <- available(instance),
         :ok <- valid_account_id(account_id) do
      id = "jido.chat/account/" <> Base.url_encode64(account_id, padding: false)
      Jido.agent_address(instance.jido(), id)
    end
  catch
    :exit, _reason -> {:error, :jido_unavailable}
  end

  defp materialize(agent, _instance, _account_id, nil, nil), do: {:ok, agent}

  defp materialize(
         agent,
         instance,
         account_id,
         %Declaration{account_id: account_id} = declaration,
         bindings
       )
       when is_list(bindings) do
    context = %{
      account_id: declaration.account_id,
      definition_key: declaration.definition_key,
      settings: declaration.settings,
      metadata: declaration.metadata
    }

    with {:ok, credentials} <-
           SecretResolver.resolve(instance.secret_resolver(), declaration.secret_refs, context),
         {:ok, agent} <- configure_chat(agent, credentials, declaration.settings, bindings) do
      {:ok, put_configuration(agent, configuration_key(declaration, bindings))}
    end
  end

  defp materialize(_agent, _instance, _account_id, _declaration, _bindings),
    do: {:error, :invalid_connection_configuration}

  defp configure_chat(agent, credentials, settings, bindings) do
    [extension] = Enum.filter(agent.plugins, &(&1.provider == Jido.Chat.Plugin))
    [connection] = extension.data.connections

    with {:ok, config} <- overlay_settings(connection.client.config, settings),
         true <- Enum.all?(bindings, &match?(%Binding{enabled: true}, &1)),
         rooms = bindings |> Enum.map(& &1.external_room_id) |> Enum.uniq() |> Enum.sort() do
      client = %{
        connection.client
        | credentials: Map.merge(connection.client.credentials || %{}, credentials),
          config: config
      }

      connection = %{connection | client: client, rooms: rooms}

      plugins =
        Enum.map(agent.plugins, fn
          %{provider: Jido.Chat.Plugin} = plugin ->
            %{plugin | data: %{plugin.data | connections: [connection]}}

          plugin ->
            plugin
        end)

      {:ok, %{agent | plugins: plugins}}
    else
      false -> {:error, :invalid_bridge_bindings}
      {:error, _reason} = error -> error
    end
  end

  defp overlay_settings(config, settings) when is_map(settings) do
    config = config || []

    if Keyword.keyword?(config) do
      known = Map.new(Keyword.keys(config), &{Atom.to_string(&1), &1})

      Enum.reduce_while(settings, {:ok, config}, fn {key, value}, {:ok, current} ->
        case Map.fetch(known, key) do
          {:ok, atom} -> {:cont, {:ok, Keyword.put(current, atom, value)}}
          :error -> {:halt, {:error, :unknown_provider_setting}}
        end
      end)
    else
      {:error, :invalid_provider_settings}
    end
  end

  defp one_connection(agent) do
    case Enum.filter(agent.plugins, &(&1.provider == Jido.Chat.Plugin)) do
      [%{data: %{connections: [_connection]}}] -> :ok
      _extensions -> {:error, :one_chat_connection_required}
    end
  end

  defp bind_bridge(agent, instance, account_id, ref, bindings) do
    bridge? = Enum.any?(agent.plugins, &(&1.provider == Bridge))

    cond do
      bridge? and is_nil(instance.storage()) ->
        {:error, :bridge_storage_required}

      is_list(bindings) and bindings != [] and not bridge? ->
        {:error, :bridge_plugin_required}

      true ->
        bind_bridge_options(agent, instance, account_id, ref, bindings)
    end
  end

  defp recover_bridge(agent, instance, account_id) do
    if Enum.any?(agent.plugins, &(&1.provider == Bridge)),
      do: Bridge.recover(instance, account_id),
      else: :ok
  end

  defp bind_bridge_options(agent, instance, account_id, ref, bindings) do
    [connection] = Enum.filter(agent.plugins, &(&1.provider == Jido.Chat.Plugin))
    [chat] = connection.data.connections
    {work_limit, queue_limit} = instance.provider_work_limits()
    mappings = if is_list(bindings), do: Enum.map(bindings, &binding_mapping/1)

    plugins =
      Enum.map(agent.plugins, fn
        %{provider: Bridge} = extension ->
          data =
            extension.data
            |> maybe_put_mappings(mappings)
            |> Map.merge(%{
              runtime: instance,
              storage: instance.storage(),
              account_id: account_id,
              account_ref: ref,
              client_id: chat.client.id,
              client_source: Jido.Chat.Signal.Identity.client_source(chat.client.id),
              provider_work_limit: work_limit,
              provider_queue_limit: queue_limit,
              provider_work_lease_ms: instance.provider_work_lease_ms()
            })

          %{extension | data: data}

        extension ->
          extension
      end)

    agent = %{agent | plugins: plugins}

    case Enum.find(agent.plugins, &(&1.provider == Bridge)) do
      nil ->
        {:ok, agent}

      extension ->
        with {:ok, normalized} <- Bridge.normalize(extension.data),
             :ok <- Bridge.verify(normalized, agent) do
          plugins =
            Enum.map(agent.plugins, fn
              %{provider: Bridge} = plugin -> %{plugin | data: normalized}
              plugin -> plugin
            end)

          {:ok, %{agent | plugins: plugins}}
        end
    end
  end

  defp binding_mapping(%Binding{} = binding) do
    %{
      name: Binding.mapping_name(binding),
      external_room: binding.external_room_id,
      room: binding.room_id,
      direction: binding.direction
    }
  end

  defp maybe_put_mappings(data, nil), do: data
  defp maybe_put_mappings(data, mappings), do: Map.put(data, :mappings, mappings)

  defp configuration_key(nil, nil), do: nil

  defp configuration_key(%Declaration{} = declaration, bindings) when is_list(bindings) do
    binding_versions =
      bindings
      |> Enum.sort_by(& &1.external_room_id)
      |> Enum.map(&{&1.external_room_id, &1.revision})

    value =
      {declaration.account_id, declaration.definition_key, declaration.revision, binding_versions}
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    "runtime/" <> value
  end

  defp configuration_key(_declaration, _bindings), do: nil

  defp put_configuration(agent, nil), do: agent

  defp put_configuration(agent, marker) do
    plugins =
      Enum.map(agent.plugins, fn
        %{provider: Jido.Chat.Plugin} = extension ->
          %{extension | data: Map.put(extension.data, :runtime_configuration, marker)}

        extension ->
          extension
      end)

    %{agent | plugins: plugins}
  end

  defp configuration_marker(agent) do
    case Enum.find(agent.plugins, &(&1.provider == Jido.Chat.Plugin)) do
      nil -> nil
      extension -> Map.get(extension.data, :runtime_configuration)
    end
  end

  defp available(instance) when is_atom(instance) do
    cond do
      not function_exported?(instance, :jido, 0) -> {:error, :invalid_runtime}
      not function_exported?(instance, :storage, 0) -> {:error, :invalid_runtime}
      not is_pid(Process.whereis(instance.jido())) -> {:error, :jido_unavailable}
      true -> :ok
    end
  end

  defp available(_instance), do: {:error, :invalid_runtime}

  defp valid_account_id(value)
       when is_binary(value) and byte_size(value) in 1..@max_account_id_bytes,
       do: :ok

  defp valid_account_id(_value), do: {:error, :invalid_account_id}
end
