defmodule Jido.Chat.AdapterTestKit.MockAdapter do
  @moduledoc """
  A deterministic adapter for contract and adapter-extension tests.

  Pass a `Jido.Chat.AdapterTestKit.MockTransport` process as `:transport` in
  operation options to record calls or supply queued provider responses.
  """

  use Jido.Chat.Adapter

  alias Jido.Chat.{AdapterTestKit.Factories, Incoming, PostPayload}
  alias Jido.Chat.AdapterTestKit.MockTransport

  @impl true
  def channel_type, do: :test

  @impl true
  def transform_incoming(payload) do
    {:ok,
     Incoming.new(%{
       external_room_id: value(payload, :external_room_id, "room-1"),
       external_user_id: value(payload, :external_user_id, "user-1"),
       external_message_id: value(payload, :external_message_id, "external-message-1"),
       external_thread_id: value(payload, :external_thread_id, "provider-thread-1"),
       text: value(payload, :text, "Hello from the test kit"),
       username: value(payload, :username, "test-user"),
       display_name: value(payload, :display_name, "Test User"),
       media: value(payload, :media, []),
       raw: payload
     })}
  end

  @impl true
  def send_message(room_id, text, opts) do
    dispatch(:send_message, %{room_id: room_id, text: text, opts: public_opts(opts)}, opts, fn ->
      {:ok, response_map(room_id, "mock-message-1", %{text: text})}
    end)
  end

  @impl true
  def send_file(room_id, file, opts) do
    dispatch(:send_file, %{room_id: room_id, file: file, opts: public_opts(opts)}, opts, fn ->
      {:ok, response_map(room_id, "mock-file-1")}
    end)
  end

  @impl true
  def post_message(room_id, %PostPayload{} = payload, opts) do
    dispatch(:post_message, %{room_id: room_id, payload: payload, opts: public_opts(opts)}, opts, fn ->
      {:ok, response_map(room_id, "mock-post-1")}
    end)
  end

  @impl true
  def edit_message(room_id, message_id, text, opts) do
    dispatch(
      :edit_message,
      %{room_id: room_id, message_id: message_id, text: text, opts: public_opts(opts)},
      opts,
      fn -> {:ok, response_map(room_id, message_id, %{text: text})} end
    )
  end

  @impl true
  def delete_message(room_id, message_id, opts) do
    dispatch(
      :delete_message,
      %{room_id: room_id, message_id: message_id, opts: public_opts(opts)},
      opts,
      fn -> :ok end
    )
  end

  @impl true
  def start_typing(room_id, opts) do
    dispatch(:start_typing, %{room_id: room_id, opts: public_opts(opts)}, opts, fn -> :ok end)
  end

  @impl true
  def fetch_message(room_id, message_id, opts) do
    dispatch(
      :fetch_message,
      %{room_id: room_id, message_id: message_id, opts: public_opts(opts)},
      opts,
      fn ->
        {:ok,
         message_for_room(room_id, %{
           id: to_string(message_id),
           external_message_id: to_string(message_id)
         })}
      end
    )
  end

  @impl true
  def fetch_media(reference, opts) do
    dispatch(:fetch_media, %{reference: reference, opts: public_opts(opts)}, opts, fn ->
      {:ok, "mock-media-bytes"}
    end)
  end

  @impl true
  def add_reaction(room_id, message_id, emoji, opts) do
    dispatch(
      :add_reaction,
      %{room_id: room_id, message_id: message_id, emoji: emoji, opts: public_opts(opts)},
      opts,
      fn -> :ok end
    )
  end

  @impl true
  def remove_reaction(room_id, message_id, emoji, opts) do
    dispatch(
      :remove_reaction,
      %{room_id: room_id, message_id: message_id, emoji: emoji, opts: public_opts(opts)},
      opts,
      fn -> :ok end
    )
  end

  @impl true
  def fetch_messages(room_id, opts), do: message_page(:fetch_messages, room_id, opts)

  @impl true
  def fetch_channel_messages(room_id, opts),
    do: message_page(:fetch_channel_messages, room_id, opts)

  @impl true
  def list_threads(room_id, opts) do
    dispatch(:list_threads, %{room_id: room_id, opts: public_opts(opts)}, opts, fn ->
      {:ok,
       %{
         threads: [
           %{
             id: "test:#{room_id}:provider-thread-1",
             root_message: message_for_room(room_id)
           }
         ],
         next_cursor: nil
       }}
    end)
  end

  @impl true
  def open_thread(room_id, message_id, opts) do
    dispatch(
      :open_thread,
      %{room_id: room_id, message_id: message_id, opts: public_opts(opts)},
      opts,
      fn ->
        {:ok,
         %{
           id: "test:#{room_id}:#{message_id}",
           adapter_name: :test,
           adapter: __MODULE__,
           external_room_id: room_id,
           external_thread_id: to_string(message_id)
         }}
      end
    )
  end

  @impl true
  def capabilities do
    %{
      send_message: :native,
      send_file: :native,
      post_message: :native,
      edit_message: :native,
      delete_message: :native,
      start_typing: :native,
      fetch_message: :native,
      fetch_media: :native,
      add_reaction: :native,
      remove_reaction: :native,
      fetch_messages: :native,
      fetch_channel_messages: :native,
      list_threads: :native,
      open_thread: :native,
      verify_webhook: :fallback,
      parse_event: :fallback,
      format_webhook_response: :fallback
    }
  end

  defp message_page(operation, room_id, opts) do
    dispatch(operation, %{room_id: room_id, opts: public_opts(opts)}, opts, fn ->
      {:ok,
       %{
         messages: [message_for_room(room_id)],
         next_cursor: nil,
         direction: :backward
       }}
    end)
  end

  defp response_map(room_id, message_id, metadata \\ %{}) do
    %{
      external_room_id: room_id,
      external_message_id: message_id,
      channel_type: :test,
      metadata: metadata
    }
  end

  defp message_for_room(room_id, overrides \\ %{}) do
    Factories.message(
      Map.merge(
        %{
          external_room_id: room_id,
          channel_id: to_string(room_id),
          thread_id: "test:#{room_id}:provider-thread-1"
        },
        overrides
      )
    )
  end

  defp dispatch(operation, payload, opts, default_fun) do
    case Keyword.get(opts, :transport) do
      nil -> default_fun.()
      transport -> MockTransport.request(transport, operation, payload, default_fun)
    end
  end

  defp public_opts(opts), do: Keyword.delete(opts, :transport)

  defp value(map, key, default) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
