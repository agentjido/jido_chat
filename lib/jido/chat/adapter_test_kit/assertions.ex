defmodule Jido.Chat.AdapterTestKit.Assertions do
  @moduledoc """
  Shared ExUnit assertions for adapter contract tests.

  These functions use only the public adapter API and canonical `Jido.Chat`
  types. They do not need a provider SDK.
  """

  import ExUnit.Assertions

  alias Jido.Chat.{
    Adapter,
    ChannelInfo,
    EphemeralMessage,
    EventEnvelope,
    Incoming,
    Media,
    Message,
    MessagePage,
    ModalResult,
    Response,
    Serialization,
    Thread,
    ThreadPage,
    WebhookResponse
  }

  @stable_statuses [:native, :fallback, :unsupported]

  @operation_specs %{
    initialize: %{result: :ok},
    shutdown: %{result: :ok},
    send_message: %{result: :response},
    send_file: %{result: :response, unsupported_call: :send_file},
    post_message: %{result: :response},
    post_channel_message: %{result: :response},
    stream: %{result: :response},
    edit_message: %{result: :response, unsupported_call: :edit_message},
    delete_message: %{result: :ok, unsupported_call: :delete_message},
    start_typing: %{result: :ok, unsupported_call: :start_typing},
    fetch_metadata: %{result: :channel_info},
    fetch_thread: %{result: :thread},
    fetch_message: %{result: :message, unsupported_call: :fetch_message},
    fetch_media: %{result: :media, unsupported_call: :fetch_media},
    add_reaction: %{result: :ok, unsupported_call: :add_reaction},
    remove_reaction: %{result: :ok, unsupported_call: :remove_reaction},
    post_ephemeral: %{result: :ephemeral_message, unsupported_call: :post_ephemeral},
    open_dm: %{result: :room_id},
    open_modal: %{result: :modal_result, unsupported_call: :open_modal},
    fetch_messages: %{result: :message_page, unsupported_call: :fetch_messages},
    fetch_channel_messages: %{
      result: :message_page,
      unsupported_call: :fetch_channel_messages
    },
    list_threads: %{result: :thread_page, unsupported_call: :list_threads},
    open_thread: %{result: :thread, unsupported_call: :open_thread},
    webhook: %{result: :webhook},
    verify_webhook: %{result: :ok},
    parse_event: %{result: :event},
    format_webhook_response: %{result: :webhook_response}
  }

  @doc "Asserts that capability statuses and native callbacks are coherent."
  @spec assert_capability_coherence(module()) :: Jido.Chat.CapabilityMatrix.t()
  def assert_capability_coherence(adapter) do
    assert_required_callbacks(adapter)
    assert_raw_capability_declaration(adapter)

    matrix = Adapter.capability_matrix(adapter)

    assert Enum.all?(matrix.capabilities, fn {_capability, status} ->
             status in @stable_statuses
           end),
           "expected all capability statuses to be :native, :fallback, or :unsupported"

    assert Adapter.validate_capabilities(adapter) == :ok
    matrix
  end

  @doc "Asserts unsupported declarations are coherent without calling provider operations."
  @spec assert_unsupported_operations(module()) :: :ok
  def assert_unsupported_operations(adapter) do
    matrix = assert_capability_coherence(adapter)

    Enum.each(@operation_specs, fn {capability, spec} ->
      if matrix.capabilities[capability] == :unsupported and spec[:unsupported_call] do
        result = call_unsupported_operation(adapter, spec.unsupported_call)

        assert result == {:error, :unsupported},
               "expected #{inspect(capability)} to return {:error, :unsupported}, " <>
                 "got: #{inspect(result)}"
      end
    end)

    :ok
  end

  @doc "Asserts a normalized `Jido.Chat.Response` result with a message identifier."
  @spec assert_normalized_response(term()) :: Response.t()
  def assert_normalized_response(result) do
    assert {:ok, %Response{} = response} = result
    assert_message_identifier(response)
    response
  end

  @doc "Asserts and returns a stable external message identifier."
  @spec assert_message_identifier(Response.t() | Message.t() | Incoming.t()) :: String.t()
  def assert_message_identifier(value) do
    identifier = message_identifier(value)

    assert not is_nil(identifier), "expected an external message identifier"

    identifier = to_string(identifier)
    assert String.trim(identifier) != "", "expected a non-empty external message identifier"
    identifier
  end

  @doc "Asserts canonical media fields and returns the media value."
  @spec assert_media(Media.t(), keyword()) :: Media.t()
  def assert_media(media, expected \\ []) do
    assert %Media{} = media

    Enum.each(expected, fn {field, expected_value} ->
      assert Map.fetch!(media, field) == expected_value,
             "expected media #{field} to equal #{inspect(expected_value)}"
    end)

    media
  end

  @doc "Asserts JSON-safe serialization and revival for a typed value."
  @spec assert_json_round_trip(struct()) :: struct()
  def assert_json_round_trip(%module{} = value) do
    assert function_exported?(module, :to_map, 1),
           "expected #{inspect(module)} to export to_map/1"

    revived =
      value
      |> module.to_map()
      |> Jason.encode!()
      |> Jason.decode!()
      |> Serialization.revive()

    assert revived == value
    revived
  end

  @doc "Asserts that a webhook request becomes a typed event envelope."
  @spec assert_webhook_event(module(), Jido.Chat.WebhookRequest.t() | map(), keyword()) ::
          EventEnvelope.t()
  def assert_webhook_event(adapter, request, opts \\ []) do
    assert {:ok, %EventEnvelope{} = envelope} = Adapter.parse_event(adapter, request, opts)
    assert envelope.adapter_name == Adapter.adapter_type(adapter)

    if envelope.event_type == :message do
      assert %Incoming{} = envelope.payload
      assert_message_identifier(envelope.payload)
      assert envelope.message_id == to_string(envelope.payload.external_message_id)
    end

    envelope
  end

  @doc """
  Asserts the normalized result shape for a declared capability.

  Use this in `capability_test/3` blocks after the provider operation runs.
  """
  @spec assert_capability_result(module(), atom(), term()) :: term()
  def assert_capability_result(adapter, capability, result) do
    case @operation_specs[capability] do
      nil ->
        flunk("unknown adapter capability #{inspect(capability)}")

      %{result: result_contract} ->
        status = Adapter.capabilities(adapter)[capability]
        assert status in [:native, :fallback], "expected #{inspect(capability)} to be supported"
        assert_supported_result(result_contract, result)
    end

    result
  end

  defp assert_supported_result(:response, result) do
    assert_normalized_response(result)
  end

  defp assert_supported_result(:ok, result), do: assert(result == :ok)

  defp assert_supported_result(:media, result) do
    assert {:ok, bytes} = result
    assert is_binary(bytes)
  end

  defp assert_supported_result(:message, result) do
    assert {:ok, %Message{} = message} = result
    assert_message_identifier(message)
  end

  defp assert_supported_result(:message_page, result) do
    assert {:ok, %MessagePage{messages: messages}} = result
    Enum.each(messages, &assert_message_identifier/1)
  end

  defp assert_supported_result(:channel_info, result),
    do: assert({:ok, %ChannelInfo{}} = result)

  defp assert_supported_result(:thread_page, result), do: assert({:ok, %ThreadPage{}} = result)
  defp assert_supported_result(:thread, result), do: assert({:ok, %Thread{}} = result)

  defp assert_supported_result(:ephemeral_message, result),
    do: assert({:ok, %EphemeralMessage{}} = result)

  defp assert_supported_result(:room_id, result) do
    assert {:ok, room_id} = result
    assert is_binary(room_id) or is_integer(room_id)
  end

  defp assert_supported_result(:modal_result, result),
    do: assert({:ok, %ModalResult{}} = result)

  defp assert_supported_result(:event, {:ok, :noop}), do: :ok
  defp assert_supported_result(:event, result), do: assert({:ok, %EventEnvelope{}} = result)

  defp assert_supported_result(:webhook_response, result),
    do: assert({:ok, %WebhookResponse{}} = result)

  defp assert_supported_result(:webhook, result),
    do: assert({:ok, %Jido.Chat{}, %Incoming{}} = result)

  defp call_unsupported_operation(adapter, :send_file),
    do: Adapter.send_file(adapter, "room-1", "/tmp/jido-chat-test-kit.txt", [])

  defp call_unsupported_operation(adapter, :edit_message),
    do: Adapter.edit_message(adapter, "room-1", "message-1", "updated", [])

  defp call_unsupported_operation(adapter, :delete_message),
    do: Adapter.delete_message(adapter, "room-1", "message-1", [])

  defp call_unsupported_operation(adapter, :start_typing),
    do: Adapter.start_typing(adapter, "room-1", [])

  defp call_unsupported_operation(adapter, :fetch_message),
    do: Adapter.fetch_message(adapter, "room-1", "message-1", [])

  defp call_unsupported_operation(adapter, :fetch_media),
    do: Adapter.fetch_media(adapter, "media://test", [])

  defp call_unsupported_operation(adapter, :add_reaction),
    do: Adapter.add_reaction(adapter, "room-1", "message-1", "thumbs_up", [])

  defp call_unsupported_operation(adapter, :remove_reaction),
    do: Adapter.remove_reaction(adapter, "room-1", "message-1", "thumbs_up", [])

  defp call_unsupported_operation(adapter, :post_ephemeral),
    do: Adapter.post_ephemeral(adapter, "room-1", "user-1", "test", [])

  defp call_unsupported_operation(adapter, :open_modal),
    do: Adapter.open_modal(adapter, "room-1", %{custom_id: "test-modal"}, [])

  defp call_unsupported_operation(adapter, :fetch_messages),
    do: Adapter.fetch_messages(adapter, "room-1", [])

  defp call_unsupported_operation(adapter, :fetch_channel_messages),
    do: Adapter.fetch_channel_messages(adapter, "room-1", [])

  defp call_unsupported_operation(adapter, :list_threads),
    do: Adapter.list_threads(adapter, "room-1", [])

  defp call_unsupported_operation(adapter, :open_thread),
    do: Adapter.open_thread(adapter, "room-1", "message-1", [])

  defp message_identifier(%Response{} = response), do: response.external_message_id
  defp message_identifier(%Message{} = message), do: message.external_message_id || message.id
  defp message_identifier(%Incoming{} = incoming), do: incoming.external_message_id

  defp assert_required_callbacks(adapter) do
    assert Code.ensure_loaded?(adapter), "expected #{inspect(adapter)} to be available"

    Enum.each([channel_type: 0, transform_incoming: 1, send_message: 3], fn {name, arity} ->
      assert function_exported?(adapter, name, arity),
             "expected #{inspect(adapter)} to export required callback #{name}/#{arity}"
    end)
  end

  defp assert_raw_capability_declaration(adapter) do
    if function_exported?(adapter, :capabilities, 0) do
      declaration = adapter.capabilities()

      assert is_map(declaration), "expected capabilities/0 to return a map"

      assert Enum.all?(declaration, fn {_capability, status} -> status in @stable_statuses end),
             "expected raw capability statuses to be :native, :fallback, or :unsupported"
    end
  end
end
