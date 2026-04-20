defmodule Jido.Chat.HandlerDispatch do
  @moduledoc false

  alias Jido.Chat.{
    ActionEvent,
    EventNormalizer,
    Incoming,
    ModalCloseEvent,
    ModalSubmitEvent,
    ReactionEvent,
    SlashCommandEvent,
    Thread
  }

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
    handlers
    |> ordered_handlers()
    |> Enum.reduce(chat, fn handler, acc -> run_event_handler(acc, handler, event) end)
  end

  defp dedupe_key(_adapter_name, %Incoming{external_message_id: nil}), do: nil

  defp dedupe_key(adapter_name, %Incoming{external_message_id: external_message_id}) do
    {adapter_name, to_string(external_message_id)}
  end

  defp duplicate?(_chat, nil), do: false

  defp duplicate?(chat, key) do
    Jido.Chat.duplicate?(chat, key)
  end

  defp mark_dedupe(chat, nil), do: chat

  defp mark_dedupe(chat, key), do: Jido.Chat.mark_dedupe(chat, key)

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

  defp run_event_handler(chat, {selector, handler}, event) do
    if selector_matches?(selector, event) do
      run_event_handler(chat, handler, event)
    else
      chat
    end
  end

  defp run_event_handler(chat, handler, event) do
    case :erlang.fun_info(handler, :arity) do
      {:arity, 2} -> coerce_handler_result(chat, handler.(chat, event))
      _ -> coerce_handler_result(chat, handler.(event))
    end
  end

  defp ordered_handlers(handlers) do
    {specific, catch_all} = Enum.split_with(handlers, &match?({_selector, _handler}, &1))
    specific ++ catch_all
  end

  defp selector_matches?(:all, _event), do: true

  defp selector_matches?(selectors, event) when is_list(selectors) do
    Enum.any?(selectors, &selector_matches?(&1, event))
  end

  defp selector_matches?(%Regex{} = pattern, event) do
    case selector_value(event) do
      value when is_binary(value) -> Regex.match?(pattern, value)
      _ -> false
    end
  end

  defp selector_matches?(selector, event) when is_function(selector, 1), do: selector.(event)

  defp selector_matches?(selector, event) when is_atom(selector) do
    selector == selector_value(event) || Atom.to_string(selector) == selector_value(event)
  end

  defp selector_matches?(selector, event) when is_binary(selector),
    do: selector == selector_value(event)

  defp selector_matches?(_selector, _event), do: false

  defp selector_value(%ReactionEvent{emoji: emoji}), do: emoji
  defp selector_value(%ActionEvent{action_id: action_id}), do: action_id
  defp selector_value(%ModalSubmitEvent{callback_id: callback_id}), do: callback_id
  defp selector_value(%ModalCloseEvent{callback_id: callback_id}), do: callback_id
  defp selector_value(%SlashCommandEvent{command: command}), do: command
  defp selector_value(_event), do: nil

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
    Jido.Chat.subscribed?(chat, thread_id)
  end
end
