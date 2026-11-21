defmodule Jido.Chat.Telegram.Streaming do
  @moduledoc false
  alias Jido.Chat.Markdown.StreamRenderer

  @doc false
  def run(client, request, opts) do
    {chunks, opts} = Keyword.pop(opts, :stream)

    with {:ok, mode} <- delivery(request.data["room_id"], Keyword.get(opts, :stream_delivery, :auto)) do
      state = %{
        client: client,
        request: request,
        opts: Keyword.delete(opts, :stream_delivery),
        mode: mode,
        draft_id: System.unique_integer([:positive]),
        interval: Map.get(request.data, "update_interval_ms", 1000),
        renderer: StreamRenderer.new(),
        text: "",
        last_text: nil,
        last_write: nil,
        message: nil
      }

      case Enum.reduce_while(chunks, {:ok, state}, &consume/2) do
        {:ok, state} -> finish(state)
        {:error, _} = error -> stream_error(error)
      end
    end
  end

  defp delivery(room, :auto), do: {:ok, if(private_chat?(room), do: :draft, else: :edit)}

  defp delivery(room, :draft) do
    if private_chat?(room), do: {:ok, :draft}, else: {:error, {:not_attempted, :invalid_stream_delivery}}
  end

  defp delivery(_room, :edit), do: {:ok, :edit}
  defp delivery(_, _), do: {:error, {:not_attempted, :invalid_stream_delivery}}

  defp private_chat?(room) do
    case Integer.parse(room) do
      {id, ""} when id > 0 -> true
      _ -> false
    end
  end

  defp consume(chunk, {:ok, state}) do
    text = Jido.Chat.StreamChunk.markdown_fallback(chunk)
    now = System.monotonic_time(:millisecond)
    due = is_nil(state.last_write) or now - state.last_write >= state.interval
    {renderer, snapshot} = snapshot(state, text, due)
    state = %{state | renderer: renderer, text: state.text <> text}

    if snapshot not in [nil, "", state.last_text] and due do
      case write(state, snapshot) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, _} = error -> {:halt, error}
      end
    else
      {:cont, {:ok, state}}
    end
  end

  defp snapshot(%{request: %{data: %{"format" => "markdown"}}} = state, text, due) do
    renderer = StreamRenderer.append(state.renderer, text)

    if due do
      {renderer, _changed} = StreamRenderer.push(renderer, "")
      {renderer, StreamRenderer.snapshot(renderer)}
    else
      {renderer, nil}
    end
  end

  defp snapshot(state, text, _due) do
    snapshot = state.text <> text
    {state.renderer, if(String.trim(snapshot) == "", do: nil, else: snapshot)}
  end

  defp finish(%{text: text}) when text == "", do: {:error, {:not_attempted, :empty_stream}}

  defp finish(state) do
    cond do
      String.trim(state.text) == "" ->
        {:error, {:not_attempted, :empty_stream}}

      state.mode == :draft ->
        stream_error(action(state, Jido.Chat.SendMessage, message_data(state, state.text)))

      state.last_text == state.text ->
        {:ok, state.message}

      true ->
        case write(state, state.text) do
          {:ok, next} -> {:ok, next.message}
          {:error, _} = error -> stream_error(error)
        end
    end
  end

  defp stream_error({:error, %Jido.Chat.Error{code: code, signal: signal}}),
    do: {:error, {:unknown, code, %{retry_after_ms: signal.data["retry_after_ms"]}}}

  defp stream_error(result), do: result

  defp write(%{mode: :draft} = state, text) do
    data =
      state.request.data
      |> Map.take(["room_id", "thread_id", "format"])
      |> Map.merge(%{"text" => text, "draft_id" => state.draft_id})

    with {:ok, _} <- action(state, Jido.Chat.Telegram.SendDraft, data) do
      {:ok, written(state, text, nil)}
    end
  end

  defp write(%{message: nil} = state, text) do
    with {:ok, message} <- action(state, Jido.Chat.SendMessage, message_data(state, text)) do
      {:ok, written(state, text, message)}
    end
  end

  defp write(state, text) do
    data =
      state.request.data
      |> Map.take(["room_id", "format", "keyboard"])
      |> Map.merge(%{"text" => text, "message_id" => state.message["id"]})

    with {:ok, message} <- action(state, Jido.Chat.EditMessage, data) do
      {:ok, written(state, text, message)}
    end
  end

  defp written(state, text, message),
    do: %{state | last_text: text, last_write: System.monotonic_time(:millisecond), message: message}

  defp message_data(state, text) do
    state.request.data
    |> Map.take(["room_id", "format", "keyboard", "thread_id", "reply_to_id"])
    |> Map.put("text", text)
  end

  defp action(state, action, data) do
    data = Map.merge(data, %{"client_id" => state.client.id, "request_id" => Jido.Id.uuid7()})

    with {:ok, signal} <-
           Jido.Chat.Signal.Policy.reply(action.signal_definition(), data, state.request, source: state.client.source),
         {:ok, completed} <- Jido.Chat.execute(state.client, signal, options: state.opts) do
      {:ok, completed.data["result"]}
    end
  end
end
