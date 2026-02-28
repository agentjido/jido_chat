defmodule Jido.Chat.HandlerDispatch do
  @moduledoc false

  alias Jido.Chat.{EventNormalizer, Incoming, Thread}

  @spec process_message(map(), atom(), String.t(), Incoming.t() | map(), (map(),
                                                                          Incoming.t(),
                                                                          String.t() ->
                                                                            Thread.t())) ::
          {:ok, map(), Incoming.t()} | {:error, term()}
  def process_message(chat, adapter_name, thread_id, incoming, build_thread)
      when is_map(chat) and is_atom(adapter_name) and is_binary(thread_id) and
             is_function(build_thread, 3) do
    with {:ok, incoming} <- EventNormalizer.ensure_incoming(incoming) do
      dedupe_key = dedupe_key(adapter_name, incoming)

      if duplicate?(chat, dedupe_key) do
        {:ok, chat, incoming}
      else
        chat = mark_dedupe(chat, dedupe_key)
        thread = build_thread.(chat, incoming, thread_id)
        routed_chat = route_handlers(chat, thread, incoming)
        {:ok, routed_chat, incoming}
      end
    end
  end

  @spec run_event_handlers(map(), list(), term()) :: map()
  def run_event_handlers(chat, handlers, event) when is_map(chat) and is_list(handlers) do
    Enum.reduce(handlers, chat, fn handler, acc -> run_event_handler(acc, handler, event) end)
  end

  defp dedupe_key(_adapter_name, %Incoming{external_message_id: nil}), do: nil

  defp dedupe_key(adapter_name, %Incoming{external_message_id: external_message_id}) do
    {adapter_name, to_string(external_message_id)}
  end

  defp duplicate?(_chat, nil), do: false

  defp duplicate?(chat, key) do
    chat
    |> Map.get(:dedupe, MapSet.new())
    |> MapSet.member?(key)
  end

  defp mark_dedupe(chat, nil), do: chat

  defp mark_dedupe(chat, key) do
    dedupe = Map.get(chat, :dedupe, MapSet.new()) |> MapSet.put(key)
    dedupe_order = Map.get(chat, :dedupe_order, []) ++ [key]
    dedupe_limit = dedupe_limit(chat)

    {trimmed_dedupe_order, overflow_keys} = trim_dedupe_order(dedupe_order, dedupe_limit)

    trimmed_dedupe =
      Enum.reduce(overflow_keys, dedupe, fn overflow_key, acc ->
        MapSet.delete(acc, overflow_key)
      end)

    chat
    |> Map.put(:dedupe, trimmed_dedupe)
    |> Map.put(:dedupe_order, trimmed_dedupe_order)
  end

  defp dedupe_limit(chat) do
    metadata = Map.get(chat, :metadata, %{})

    value =
      case metadata do
        %{} -> metadata[:dedupe_limit] || metadata["dedupe_limit"]
        _ -> nil
      end

    if is_integer(value) and value > 0, do: value, else: 1_000
  end

  defp trim_dedupe_order(dedupe_order, dedupe_limit) do
    overflow_count = max(length(dedupe_order) - dedupe_limit, 0)

    if overflow_count == 0 do
      {dedupe_order, []}
    else
      {overflow_keys, remaining_keys} = Enum.split(dedupe_order, overflow_count)
      {remaining_keys, overflow_keys}
    end
  end

  defp route_handlers(chat, %Thread{} = thread, %Incoming{} = incoming) do
    cond do
      subscribed?(chat, thread.id) ->
        run_handlers(chat, chat.handlers.subscribed, thread, incoming)

      mentioned?(chat, incoming) ->
        run_handlers(chat, chat.handlers.mention, thread, incoming)

      true ->
        run_message_handlers(chat, thread, incoming)
    end
  end

  defp run_message_handlers(chat, %Thread{} = thread, %Incoming{} = incoming) do
    text = incoming.text || ""

    Enum.reduce(chat.handlers.message, chat, fn {pattern, handler}, acc ->
      if Regex.match?(pattern, text) do
        run_handler(acc, handler, thread, incoming)
      else
        acc
      end
    end)
  end

  defp run_handlers(chat, handlers, %Thread{} = thread, %Incoming{} = incoming) do
    Enum.reduce(handlers, chat, fn handler, acc -> run_handler(acc, handler, thread, incoming) end)
  end

  defp run_handler(chat, handler, %Thread{} = thread, %Incoming{} = incoming) do
    case :erlang.fun_info(handler, :arity) do
      {:arity, 3} ->
        coerce_handler_result(chat, handler.(chat, thread, incoming))

      _ ->
        coerce_handler_result(chat, handler.(thread, incoming))
    end
  end

  defp run_event_handler(chat, handler, event) do
    case :erlang.fun_info(handler, :arity) do
      {:arity, 2} -> coerce_handler_result(chat, handler.(chat, event))
      _ -> coerce_handler_result(chat, handler.(event))
    end
  end

  defp coerce_handler_result(current_chat, next_chat) when is_map(next_chat) do
    if Map.get(next_chat, :__struct__) == Jido.Chat do
      next_chat
    else
      current_chat
    end
  end

  defp coerce_handler_result(current_chat, {:ok, next_chat}) when is_map(next_chat) do
    if Map.get(next_chat, :__struct__) == Jido.Chat do
      next_chat
    else
      current_chat
    end
  end

  defp coerce_handler_result(current_chat, _other), do: current_chat

  defp mentioned?(_chat, %Incoming{was_mentioned: true}), do: true

  defp mentioned?(chat, %Incoming{text: text}) when is_binary(text) do
    mention_regex = ~r/(^|\s)@#{Regex.escape(Map.get(chat, :user_name, "bot"))}\b/i
    Regex.match?(mention_regex, text)
  end

  defp mentioned?(_chat, _incoming), do: false

  defp subscribed?(chat, thread_id) do
    chat
    |> Map.get(:subscriptions, MapSet.new())
    |> MapSet.member?(thread_id)
  end
end
