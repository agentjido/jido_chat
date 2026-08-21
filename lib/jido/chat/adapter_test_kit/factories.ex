defmodule Jido.Chat.AdapterTestKit.Factories do
  @moduledoc """
  Deterministic factories for adapter contract tests.

  Each factory returns a public `Jido.Chat` type. Factories accept a map or a
  keyword list of shallow field overrides.
  """

  alias Jido.Chat.{
    Author,
    EventEnvelope,
    Incoming,
    Media,
    Message,
    PostPayload,
    Response,
    WebhookRequest
  }

  @doc "Builds a canonical author."
  @spec author(map() | keyword()) :: Author.t()
  def author(overrides \\ %{}) do
    %{
      user_id: "user-1",
      user_name: "test-user",
      full_name: "Test User",
      is_bot: false,
      is_me: false,
      metadata: %{"source" => "adapter-test-kit"}
    }
    |> merge(overrides)
    |> Author.new()
  end

  @doc "Builds canonical media."
  @spec media(map() | keyword()) :: Media.t()
  def media(overrides \\ %{}) do
    overrides = to_map(overrides)
    kind = Map.get(overrides, :kind, Map.get(overrides, "kind", :image))

    kind
    |> media_defaults()
    |> Map.merge(overrides)
    |> Media.new()
  end

  @doc "Builds a canonical incoming message."
  @spec incoming(map() | keyword()) :: Incoming.t()
  def incoming(overrides \\ %{}) do
    %{
      external_room_id: "room-1",
      external_user_id: "user-1",
      external_message_id: "external-message-1",
      external_thread_id: "provider-thread-1",
      text: "Hello from the test kit",
      author: author(),
      username: "test-user",
      display_name: "Test User",
      timestamp: "2026-01-02T03:04:05Z",
      chat_type: :channel,
      was_mentioned: false,
      media: [media()],
      raw: %{"provider" => "fixture"},
      metadata: %{"source" => "adapter-test-kit"}
    }
    |> merge(overrides)
    |> Incoming.new()
  end

  @doc "Builds a canonical normalized message."
  @spec message(map() | keyword()) :: Message.t()
  def message(overrides \\ %{}) do
    %{
      id: "message-1",
      thread_id: "test:room-1:provider-thread-1",
      channel_id: "room-1",
      text: "Hello from the test kit",
      formatted: "Hello from the test kit",
      author: author(),
      attachments: [media()],
      created_at: "2026-01-02T03:04:05Z",
      external_message_id: "external-message-1",
      external_room_id: "room-1",
      metadata: %{"source" => "adapter-test-kit"},
      raw: %{"provider" => "fixture"}
    }
    |> merge(overrides)
    |> Message.new()
  end

  @doc "Builds a canonical message event envelope."
  @spec event(map() | keyword()) :: EventEnvelope.t()
  def event(overrides \\ %{}) do
    %{
      id: "event-1",
      adapter_name: :test,
      event_type: :message,
      thread_id: "test:room-1:provider-thread-1",
      channel_id: "room-1",
      message_id: "external-message-1",
      payload: incoming(),
      raw: %{"provider" => "fixture"},
      metadata: %{"source" => "adapter-test-kit"}
    }
    |> merge(overrides)
    |> EventEnvelope.new()
  end

  @doc "Builds a canonical webhook request."
  @spec webhook_request(map() | keyword()) :: WebhookRequest.t()
  def webhook_request(overrides \\ %{}) do
    %{
      adapter_name: :test,
      method: "POST",
      path: "/webhooks/test",
      headers: %{"content-type" => "application/json", "x-test-signature" => "valid"},
      payload: %{
        "external_room_id" => "room-1",
        "external_user_id" => "user-1",
        "external_message_id" => "external-message-1",
        "external_thread_id" => "provider-thread-1",
        "text" => "Hello from the test kit"
      },
      metadata: %{"source" => "adapter-test-kit"}
    }
    |> merge(overrides)
    |> WebhookRequest.new()
  end

  @doc "Builds a canonical adapter response."
  @spec response(map() | keyword()) :: Response.t()
  def response(overrides \\ %{}) do
    %{
      external_message_id: "external-message-1",
      external_room_id: "room-1",
      timestamp: "2026-01-02T03:04:05Z",
      channel_type: :test,
      status: :sent,
      raw: %{"provider" => "fixture"},
      metadata: %{"source" => "adapter-test-kit"}
    }
    |> merge(overrides)
    |> Response.new()
  end

  @doc "Builds a canonical outbound post payload."
  @spec post_payload(map() | keyword()) :: PostPayload.t()
  def post_payload(overrides \\ %{}) do
    %{
      text: "Hello from the test kit",
      metadata: %{"source" => "adapter-test-kit"}
    }
    |> merge(overrides)
    |> PostPayload.new()
  end

  defp media_defaults(kind) when kind in [:image, "image"] do
    %{
      kind: :image,
      url: "https://example.test/sample.png",
      media_type: "image/png",
      filename: "sample.png",
      size_bytes: 128,
      width: 16,
      height: 16,
      metadata: %{"source" => "adapter-test-kit"}
    }
  end

  defp media_defaults(kind) when kind in [:audio, "audio"] do
    %{
      kind: :audio,
      url: "https://example.test/sample.mp3",
      media_type: "audio/mpeg",
      filename: "sample.mp3",
      size_bytes: 128,
      duration: 1,
      metadata: %{"source" => "adapter-test-kit"}
    }
  end

  defp media_defaults(kind) when kind in [:video, "video"] do
    %{
      kind: :video,
      url: "https://example.test/sample.mp4",
      media_type: "video/mp4",
      filename: "sample.mp4",
      size_bytes: 128,
      width: 16,
      height: 16,
      duration: 1,
      metadata: %{"source" => "adapter-test-kit"}
    }
  end

  defp media_defaults(_kind) do
    %{
      kind: :file,
      url: "https://example.test/sample.txt",
      media_type: "text/plain",
      filename: "sample.txt",
      size_bytes: 128,
      metadata: %{"source" => "adapter-test-kit"}
    }
  end

  defp merge(defaults, overrides), do: Map.merge(defaults, to_map(overrides))
  defp to_map(overrides) when is_map(overrides), do: overrides
  defp to_map(overrides) when is_list(overrides), do: Map.new(overrides)
end
