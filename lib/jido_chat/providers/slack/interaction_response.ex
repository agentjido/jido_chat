defmodule Jido.Chat.Slack.InteractionResponse do
  @moduledoc "Builds Slack HTTP and Socket Mode response payloads."

  @doc "Builds an optional plain webhook response map."
  def webhook_response(result, opts \\ []) do
    context = %{mode: :webhook, result: result, request: opts[:request]}

    case response_value(context, opts) do
      nil -> nil
      %{} = response -> response
      response when is_binary(response) -> %{status: 200, body: response}
      _ -> nil
    end
  end

  @doc "Builds a Socket Mode acknowledgement for one envelope."
  def socket_ack_payload(envelope, sink_result, opts \\ []) do
    ack = %{"envelope_id" => field(envelope, "envelope_id")}

    if field(envelope, "accepts_response_payload") == true do
      context = %{
        mode: :socket_mode,
        envelope: envelope,
        payload: field(envelope, "payload"),
        sink_result: sink_result
      }

      case normalize_socket_payload(response_value(context, opts)) do
        nil -> ack
        payload -> Map.put(ack, "payload", payload)
      end
    else
      ack
    end
  end

  defp response_value(context, opts) do
    opts[:slack_response] || opts[:response_payload] ||
      call_builder(opts[:response_builder] || opts[:slack_response_builder], context, opts) ||
      response_from_result(context)
  end

  defp call_builder(nil, _, _), do: nil
  defp call_builder(builder, context, _) when is_function(builder, 1), do: builder.(context)
  defp call_builder(builder, context, opts) when is_function(builder, 2), do: builder.(context, opts)

  defp call_builder({module, function, args}, context, _)
       when is_atom(module) and is_atom(function) and is_list(args),
       do: apply(module, function, args ++ [context])

  defp call_builder(_, _, _), do: nil

  defp response_from_result(%{sink_result: {:reply, response}}), do: response
  defp response_from_result(%{sink_result: {:ok, {:reply, response}}}), do: response
  defp response_from_result(%{result: {:reply, response}}), do: response
  defp response_from_result(%{result: {:ok, {:reply, response}}}), do: response
  defp response_from_result(_), do: nil

  defp normalize_socket_payload(nil), do: nil
  defp normalize_socket_payload(%{body: body}), do: normalize_socket_payload(body)
  defp normalize_socket_payload(%{"body" => body}), do: normalize_socket_payload(body)
  defp normalize_socket_payload(%{} = response), do: response
  defp normalize_socket_payload(response) when is_binary(response), do: %{"text" => response}
  defp normalize_socket_payload(_), do: nil

  defp field(map, key) do
    Map.get(map, key) ||
      Enum.find_value(map, fn
        {atom, value} when is_atom(atom) -> if Atom.to_string(atom) == key, do: value
        _ -> nil
      end)
  end
end
