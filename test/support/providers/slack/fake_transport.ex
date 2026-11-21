defmodule Jido.Chat.Slack.TestTransport do
  @moduledoc false

  @behaviour Jido.Chat.Slack.Transport

  @impl true
  def send_message(token, room_id, text, opts) do
    report(opts, {:send_message, token, room_id, text, opts})
    {:ok, %{"channel" => room_id, "ts" => "1700000000.000001", "text" => text, "user" => "B1"}}
  end

  @impl true
  def send_file(token, room_id, upload, opts) do
    report(opts, {:send_file, token, room_id, upload, opts})

    {:ok,
     %{
       "files" => [
         %{
           "id" => "F1",
           "shares" => %{"private" => %{room_id => [%{"ts" => "1700000000.000002"}]}}
         }
       ]
     }}
  end

  @impl true
  def edit_message(token, room_id, message_id, text, opts) do
    report(opts, {:edit_message, token, room_id, message_id, text, opts})
    {:ok, %{"channel" => room_id, "ts" => message_id, "text" => text, "user" => "B1"}}
  end

  @impl true
  def delete_message(token, room_id, message_id, opts) do
    report(opts, {:delete_message, token, room_id, message_id, opts})
    {:ok, true}
  end

  @impl true
  def fetch_metadata(token, room_id, opts) do
    report(opts, {:fetch_metadata, token, room_id, opts})
    {:ok, %{"id" => room_id, "name" => "general", "topic" => %{"value" => "General"}}}
  end

  @impl true
  def fetch_thread(token, room_id, thread_id, opts) do
    report(opts, {:fetch_thread, token, room_id, thread_id, opts})

    {:ok,
     %{
       "messages" => [
         %{"ts" => thread_id, "text" => "root", "user" => "U1"},
         %{"ts" => "1700000000.000004", "text" => "reply", "user" => "U2", "thread_ts" => thread_id}
       ],
       "response_metadata" => %{"next_cursor" => ""}
     }}
  end

  @impl true
  def fetch_message(token, room_id, message_id, opts) do
    report(opts, {:fetch_message, token, room_id, message_id, opts})
    {:ok, %{"channel" => room_id, "ts" => message_id, "text" => "message", "user" => "U1"}}
  end

  @impl true
  def get_user(token, user_id, opts) do
    report(opts, {:get_user, token, user_id, opts})

    {:ok,
     %{
       "id" => user_id,
       "name" => String.downcase(user_id),
       "is_bot" => false,
       "profile" => %{"display_name" => user_id}
     }}
  end

  @impl true
  def mark_as_read(token, room_id, message_id, opts) do
    report(opts, {:mark_as_read, token, room_id, message_id, opts})
    {:ok, true}
  end

  @impl true
  def download_file(token, url, opts) do
    report(opts, {:download_file, token, url, opts})
    {:ok, "file bytes"}
  end

  @impl true
  def fetch_messages(token, room_id, opts) do
    report(opts, {:fetch_messages, token, room_id, opts})

    {:ok,
     %{
       "messages" => [%{"channel" => room_id, "ts" => "1700000000.000003", "text" => "page", "user" => "U1"}],
       "response_metadata" => %{"next_cursor" => "next"}
     }}
  end

  @impl true
  def list_threads(token, room_id, opts) do
    report(opts, {:list_threads, token, room_id, opts})

    {:ok,
     %{
       "threads" => [%{"ts" => "1700000000.000003", "text" => "thread"}],
       "response_metadata" => %{"next_cursor" => ""}
     }}
  end

  @impl true
  def add_reaction(token, room_id, message_id, reaction, opts) do
    report(opts, {:add_reaction, token, room_id, message_id, reaction, opts})
    {:ok, true}
  end

  @impl true
  def remove_reaction(token, room_id, message_id, reaction, opts) do
    report(opts, {:remove_reaction, token, room_id, message_id, reaction, opts})
    {:ok, true}
  end

  @impl true
  def post_ephemeral(token, room_id, user_id, text, opts) do
    report(opts, {:post_ephemeral, token, room_id, user_id, text, opts})
    {:ok, %{"channel" => room_id, "message_ts" => "1700000000.000005", "text" => text, "user" => "B1"}}
  end

  @impl true
  def open_dm(token, user_id, opts) do
    report(opts, {:open_dm, token, user_id, opts})
    {:ok, "D1"}
  end

  @impl true
  def open_modal(token, trigger_id, payload, opts) do
    report(opts, {:open_modal, token, trigger_id, payload, opts})
    {:ok, %{"view" => %{"id" => "V1"}}}
  end

  defp report(opts, message) do
    if pid = opts[:test_pid], do: send(pid, message)
  end
end
