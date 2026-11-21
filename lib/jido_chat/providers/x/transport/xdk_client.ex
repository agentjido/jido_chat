defmodule Jido.Chat.X.Transport.XdkClient do
  @moduledoc "XDK-backed transport for X Direct Messages."
  @behaviour Jido.Chat.X.Transport

  alias Jido.Chat.Providers.Dependencies

  @impl true
  def send_dm(participant_id, text, opts) do
    request(:create_by_participant_id, [participant_id, %{"text" => text}], opts)
  end

  @impl true
  def send_conversation_message(conversation_id, text, opts) do
    request(:create_by_conversation_id, [conversation_id, %{"text" => text}], opts)
  end

  @impl true
  def delete_dm_event(event_id, opts) do
    case request(:delete_events, [event_id], opts) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @impl true
  def fetch_dm_event(event_id, opts) do
    request(:get_events_by_id, [event_id, query_opts(opts)], opts)
  end

  @impl true
  def fetch_conversation_messages(conversation_id, opts) do
    request(:get_events_by_conversation_id, [conversation_id, query_opts(opts)], opts)
  end

  defp request(method, args, opts) do
    with :ok <- Dependencies.check(xdk_elixir: Xdk.DirectMessages) do
      apply(Xdk.DirectMessages, method, [client!(opts) | args])
    end
  end

  defp query_opts(opts) do
    opts
    |> Keyword.take([
      :expansions,
      :dm_event_fields,
      :user_fields,
      :media_fields,
      :pagination_token,
      :max_results
    ])
    |> then(fn query ->
      if opts[:cursor], do: Keyword.put(query, :pagination_token, opts[:cursor]), else: query
    end)
    |> then(fn query ->
      if opts[:limit], do: Keyword.put(query, :max_results, opts[:limit]), else: query
    end)
  end

  defp client!(opts) do
    Keyword.get(opts, :xdk_client) ||
      raise ArgumentError, "missing :xdk_client option for X adapter transport"
  end
end
