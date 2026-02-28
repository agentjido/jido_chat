defmodule Jido.Chat.ChannelTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Channel

  defmodule LegacyChannel do
    @behaviour Channel

    @impl true
    def channel_type, do: :legacy

    @impl true
    def transform_incoming(%{text: text}),
      do: {:ok, %{external_room_id: "room", external_user_id: "user", text: text}}

    @impl true
    def send_message(_chat_id, _text, _opts), do: {:ok, %{message_id: "sent"}}
  end

  defmodule V2AlignedChannel do
    @behaviour Channel

    @impl true
    def channel_type, do: :v2

    @impl true
    def capabilities, do: [:text, :command_hints]

    @impl true
    def transform_incoming(_),
      do: {:ok, %{external_room_id: "room", external_user_id: "user", text: "hi"}}

    @impl true
    def send_message(_, _, _), do: {:ok, %{message_id: "sent"}}

    @impl true
    def extract_command_hint(_), do: {:ok, %{name: "ping"}}
  end

  defmodule MismatchedCapabilityChannel do
    @behaviour Channel

    @impl true
    def channel_type, do: :mismatch

    @impl true
    def capabilities, do: [:text, :command_hints]

    @impl true
    def transform_incoming(_),
      do: {:ok, %{external_room_id: "room", external_user_id: "user", text: "hi"}}

    @impl true
    def send_message(_, _, _), do: {:ok, %{message_id: "sent"}}
  end

  test "v1-only channels get deterministic v2 defaults" do
    incoming = %{external_room_id: "room", external_user_id: "user", text: "hello"}

    assert {:ok, []} = Channel.listener_child_specs(LegacyChannel, "inst")
    assert {:ok, %{}} = Channel.extract_routing_metadata(LegacyChannel, %{"raw" => true})
    assert :ok = Channel.verify_sender(LegacyChannel, incoming, %{"raw" => true})
    assert {:ok, "hello"} = Channel.sanitize_outbound(LegacyChannel, "hello")
    assert {:ok, nil} = Channel.extract_command_hint(LegacyChannel, incoming)
  end

  test "capability contract validation detects missing callbacks" do
    assert :ok = Channel.validate_capability_contract(V2AlignedChannel)
    assert {:error, [failure]} = Channel.validate_capability_contract(MismatchedCapabilityChannel)
    assert failure.reason == :missing_callback
    assert failure.callback == :extract_command_hint
  end

  test "compile-time contract check via use Jido.Chat.Channel" do
    module_name = Module.concat(__MODULE__, :CompileMismatch)

    code = """
    defmodule #{inspect(module_name)} do
      use Jido.Chat.Channel

      @impl true
      def channel_type, do: :compile_mismatch

      @impl true
      def capabilities, do: [:command_hints]

      @impl true
      def transform_incoming(_payload) do
        {:ok, %{external_room_id: \"room\", external_user_id: \"user\", text: \"hello\"}}
      end

      @impl true
      def send_message(_chat_id, _text, _opts), do: {:ok, %{message_id: \"sent\"}}
    end
    """

    assert_raise CompileError, ~r/channel capability contract failed/, fn ->
      Code.compile_string(code)
    end
  end
end
