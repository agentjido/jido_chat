defmodule Jido.Chat.Operations.Invocation do
  @moduledoc false

  alias Jido.Chat.{Card, FileUpload, Modal, PostPayload, Resources}
  alias Jido.Chat.Signal.Policy
  alias Jido.Chat.Markdown.StreamRenderer

  @option_keys %{
    "thread_id" => :thread_id,
    "reply_to_id" => :reply_to_id,
    "format" => :format,
    "cursor" => :cursor,
    "limit" => :limit,
    "direction" => :direction,
    "topic_name" => :topic_name,
    "fallback_to_dm" => :fallback_to_dm
  }
  @fallbacks [
    :post_message,
    :fetch_metadata,
    :fetch_thread,
    :fetch_subject,
    :post_channel_message,
    :post_ephemeral,
    :stream
  ]

  @doc false
  @spec run(Jido.Chat.Binding.t(), Jido.Signal.t(), tuple()) :: term()
  def run(binding, request, definition) do
    with {:ok, prepared} <- prepare(binding, request, definition),
         do: invoke(prepared)
  end

  @doc false
  def prepare(binding, request, {_module, operation, fields, _shape, _schema}) do
    {:ok, matrix} = Jido.Chat.Operations.Capabilities.read(binding.adapter)
    status = Map.get(matrix, operation, :unsupported)

    if status == :native or (status == :fallback and operation in @fallbacks) do
      with {:ok, arguments} <- arguments(binding, request, operation, fields) do
        opts = options(binding, request.data)
        mode = if matrix[:edit_message] == :native, do: Keyword.get(opts, :fallback_mode, :post_edit), else: :final
        {:ok, {binding, status, operation, arguments, opts, mode}}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc false
  def invoke({binding, :native, operation, arguments, opts, _mode}),
    do: native(binding.adapter, operation, arguments ++ [opts])

  def invoke({binding, :fallback, :stream, arguments, opts, mode}),
    do: stream_fallback(binding, arguments, opts, mode)

  def invoke({binding, :fallback, operation, arguments, opts, _mode}),
    do: fallback(binding, operation, arguments, opts)

  defp arguments(_binding, request, :load_options, _fields), do: {:ok, [request]}

  defp arguments(binding, request, operation, fields) do
    Enum.reduce_while(fields, {:ok, []}, fn field, {:ok, acc} ->
      value = request.data[field]

      result =
        case field do
          "resource_ref" -> resolve(binding, value, if(operation == :stream, do: ~w(stream), else: ~w(file media)))
          "media_ref" -> resolve(binding, value, ~w(media))
          "content" -> content(binding, value)
          "modal" -> resolve(binding, value, ~w(modal)) |> modal()
          _ -> {:ok, value}
        end

      case result do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp resolve(binding, %{"kind" => kind} = ref, kinds) do
    if kind in kinds, do: Resources.resolve(binding, ref), else: Policy.error(:invalid_resource)
  end

  defp resolve(_binding, _ref, _kinds), do: Policy.error(:invalid_resource)
  defp modal({:ok, %Modal{} = modal}), do: {:ok, modal}
  defp modal({:ok, _}), do: Policy.error(:invalid_resource)
  defp modal(error), do: error

  defp content(_binding, %{"kind" => "text", "text" => text}), do: {:ok, PostPayload.text(text)}

  defp content(_binding, %{"kind" => "markdown", "text" => text}),
    do: {:ok, PostPayload.new(%{kind: :markdown, markdown: text})}

  defp content(binding, %{"kind" => "card", "resource_ref" => ref} = content) do
    with {:ok, %Card{} = card} <- resolve(binding, ref, ~w(card)) do
      {:ok, PostPayload.new(%{kind: :card, card: card, fallback_text: content["fallback_text"]})}
    else
      {:error, _} = error -> error
      _ -> Policy.error(:invalid_resource)
    end
  end

  defp content(binding, %{"kind" => "stream", "resource_ref" => ref} = content) do
    with {:ok, stream} <- resolve(binding, ref, ~w(stream)),
         do: {:ok, PostPayload.stream(stream, fallback_text: content["fallback_text"])}
  end

  defp content(binding, %{"kind" => "media", "resource_ref" => ref} = content) do
    with {:ok, %FileUpload{} = file} <- resolve(binding, ref, ~w(file media)) do
      {:ok,
       PostPayload.new(%{
         files: [file],
         text: content["caption"] || content["fallback_text"],
         fallback_text: content["fallback_text"]
       })}
    else
      {:error, _} = error -> error
      _ -> Policy.error(:invalid_resource)
    end
  end

  defp content(_binding, _value), do: Policy.error(:invalid_resource)

  defp options(binding, data) do
    Enum.reduce(@option_keys, binding.options, fn {key, option}, acc ->
      case Map.fetch(data, key) do
        {:ok, value} ->
          value =
            if key == "direction", do: Enum.find([:forward, :backward], &(Atom.to_string(&1) == value)), else: value

          Keyword.put(acc, option, value)

        :error ->
          acc
      end
    end)
  end

  defp native(adapter, :load_options, [request, opts]) do
    timeout = Keyword.get(opts, :timeout_ms, 5_000)

    if is_integer(timeout) and timeout > 0 do
      parent = self()
      tag = make_ref()
      deadline = System.monotonic_time(:millisecond) + timeout

      {pid, monitor} =
        spawn_monitor(fn -> guard_options(parent, tag, adapter, request, opts, deadline) end)

      receive do
        {^tag, result} ->
          Process.demonitor(monitor, [:flush])
          result

        {:DOWN, ^monitor, :process, ^pid, _reason} ->
          {:error, {:task_exit, :provider_failure}}
      end
    else
      Policy.error(:invalid_request, :timeout_ms)
    end
  end

  defp native(adapter, operation, args) do
    if function_exported?(adapter, operation, length(args)),
      do: apply(adapter, operation, args),
      else: {:error, :unsupported}
  end

  defp guard_options(parent, tag, adapter, request, opts, deadline) do
    Process.flag(:trap_exit, true)
    owner_monitor = Process.monitor(parent)
    guardian = self()
    worker = spawn_link(fn -> send(guardian, {tag, load_options(adapter, request, opts)}) end)
    timeout = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^tag, result} ->
        send(parent, {tag, result})

      {:EXIT, ^worker, _reason} ->
        send(parent, {tag, {:error, {:task_exit, :provider_failure}}})

      {:DOWN, ^owner_monitor, :process, ^parent, _reason} ->
        stop_options(worker)
    after
      timeout ->
        stop_options(worker)
        send(parent, {tag, {:error, :timeout}})
    end
  end

  defp stop_options(worker) do
    Process.exit(worker, :kill)

    receive do
      {:EXIT, ^worker, _reason} -> :ok
    end
  end

  defp load_options(adapter, request, opts) do
    apply(adapter, :load_options, [request, opts])
  rescue
    _ -> {:error, {:exception, :provider_failure}}
  catch
    _, _ -> {:error, {:exception, :provider_failure}}
  end

  defp fallback(_binding, :fetch_metadata, [room], _opts), do: {:ok, %{"id" => room, "kind" => "unknown"}}
  defp fallback(_binding, :fetch_thread, [room], _opts), do: {:ok, %{"id" => room, "room_id" => room}}

  defp fallback(binding, :fetch_subject, [room], opts) do
    with {:ok, thread} <- native(binding.adapter, :fetch_thread, [room, opts]),
         {:ok, value} <- Jido.Chat.Operations.Result.project(:thread, thread, %{"room_id" => room}) do
      {:ok, Map.put(value, "kind", "thread")}
    end
  end

  defp fallback(binding, :post_channel_message, [room, text], opts),
    do: native(binding.adapter, :send_message, [room, text, opts])

  defp fallback(binding, :post_message, [room, %PostPayload{} = payload], opts) do
    case PostPayload.upload_candidates(payload) do
      [] -> native(binding.adapter, :send_message, [room, PostPayload.display_text(payload) || "", opts])
      [file] -> native(binding.adapter, :send_file, [room, file, Keyword.put(opts, :caption, payload.text)])
      _ -> {:error, :unsupported}
    end
  end

  defp fallback(binding, :post_ephemeral, [_room, user, text], opts) do
    if Keyword.get(opts, :fallback_to_dm, false) do
      with {:ok, dm} <- native(binding.adapter, :open_dm, [user, opts]),
           {:ok, room} <- dm_room(dm) do
        native(binding.adapter, :send_message, [room, text, Keyword.delete(opts, :fallback_to_dm)])
      end
    else
      {:error, :unsupported}
    end
  end

  defp stream_fallback(binding, [room, chunks], opts, mode) do
    chunks = Enum.to_list(chunks)

    if mode == :post_edit do
      stream_edit(binding, room, chunks, opts)
    else
      case StreamRenderer.render(chunks) do
        nil -> {:error, :provider_failure}
        text -> native(binding.adapter, :send_message, [room, text, opts])
      end
    end
  end

  defp dm_room(dm) do
    {_, _, _, shape, schema} =
      Jido.Chat.Operations.Definitions.lookup(Jido.Chat.Signal.OpenDm.type())

    with {:ok, result} <- Jido.Chat.Operations.Result.project(shape, dm, %{}),
         {:ok, result} <- Zoi.parse(schema, result),
         :ok <- Policy.validate_json(result, []) do
      {:ok, result["id"]}
    else
      _ -> {:error, :invalid_provider_result}
    end
  end

  defp stream_edit(binding, room, chunks, opts) do
    update_every =
      case Keyword.get(opts, :update_every, 1) do
        value when is_integer(value) and value > 0 -> value
        _ -> 1
      end

    initial = %{renderer: StreamRenderer.new(), response: nil, last_text: nil}
    placeholder = Keyword.get(opts, :placeholder_text, "Working...")

    with {:ok, initial} <- stream_text(binding, room, opts, initial, placeholder),
         {:ok, state} <- stream_chunks(binding, room, chunks, opts, update_every, initial),
         {:ok, state} <- stream_text(binding, room, opts, state, StreamRenderer.flush(state.renderer)) do
      if is_nil(state.response), do: {:error, :invalid_provider_result}, else: {:ok, state.response}
    end
  end

  defp stream_chunks(binding, room, chunks, opts, update_every, initial) do
    total = length(chunks)

    chunks
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, initial}, fn {chunk, index}, {:ok, state} ->
      {renderer, text} =
        if rem(index, update_every) == 0 or index == total do
          {renderer, _} = StreamRenderer.push(state.renderer, chunk)
          {renderer, StreamRenderer.snapshot(renderer)}
        else
          {StreamRenderer.append(state.renderer, chunk), nil}
        end

      case stream_text(binding, room, opts, %{state | renderer: renderer}, text) do
        {:ok, state} -> {:cont, {:ok, state}}
        error -> {:halt, error}
      end
    end)
  end

  defp stream_text(_binding, _room, _opts, state, nil), do: {:ok, state}
  defp stream_text(_binding, _room, _opts, %{last_text: text} = state, text), do: {:ok, state}

  defp stream_text(binding, room, opts, state, text) do
    cond do
      not is_binary(text) ->
        {:error, :invalid_provider_result}

      String.trim(text) == "" ->
        {:ok, state}

      is_nil(state.response) ->
        with {:ok, response} <- native(binding.adapter, :send_message, [room, text, opts]) do
          {:ok, %{state | response: response, last_text: text}}
        end

      true ->
        with {:ok, message} <- Jido.Chat.Operations.Result.project(:message, state.response, %{"room_id" => room}),
             id when is_binary(id) <- message["id"],
             {:ok, response} <- native(binding.adapter, :edit_message, [room, id, text, opts]) do
          {:ok, %{state | response: response, last_text: text}}
        else
          {:error, _} = error -> error
          _ -> {:error, :invalid_provider_result}
        end
    end
  end
end
