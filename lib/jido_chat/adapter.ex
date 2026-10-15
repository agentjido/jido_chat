defmodule Jido.Chat.Adapter do
  @moduledoc """
  Protocol version 1 provider contract.

  Bind once with `Jido.Chat.bind/2`. Public requests and results are typed
  Signals. Operation callbacks are private provider calls selected only by the
  direct executor. A normalizer returns a complete ordered delivery of facts.
  Verification, listener setup, acknowledgement, and provisioning are private
  transport controls. A Bus-published request cannot invoke these callbacks.
  """

  alias Jido.Chat.{
    Binding,
    Card,
    CapabilityMatrix,
    Delivery,
    Markdown,
    Modal,
    PostPayload,
    WebhookRequest,
    WebhookResponse
  }

  @type capability_status :: :native | :fallback | :unsupported
  @type capability_matrix :: %{optional(atom()) => capability_status()}
  @type provider_result :: {:ok, term()} | {:error, term()} | :ok
  @type raw_payload :: term()
  @type external_room_id :: String.t()
  @type external_message_id :: String.t()
  @type external_user_id :: String.t()
  @type file_input :: Jido.Chat.FileUpload.input()
  @type media_reference :: term()
  @type listener_opts :: keyword()

  @doc "Returns the explicitly implemented Signal protocol version."
  @callback signal_protocol() :: pos_integer()
  @doc "Captures resolved private transport, credentials, and resources at setup."
  @callback configure_binding(keyword()) :: {:ok, keyword()} | {:error, term()}
  @doc "Normalizes a private provider input into a complete validated delivery."
  @callback normalize_event(Binding.t(), term()) :: {:ok, Delivery.t()} | {:error, Jido.Chat.Errors.Contract.t()}
  @callback channel_type() :: atom()
  @callback capabilities() :: capability_matrix()
  @callback initialize(keyword()) :: :ok | {:ok, term()} | {:error, term()}
  @callback shutdown(keyword()) :: :ok | {:ok, term()} | {:error, term()}
  @callback send_message(external_room_id(), String.t(), keyword()) :: provider_result()
  @callback send_file(external_room_id(), file_input(), keyword()) :: provider_result()
  @callback post_message(external_room_id(), PostPayload.t(), keyword()) :: provider_result()
  @callback edit_message(external_room_id(), external_message_id(), String.t(), keyword()) :: provider_result()
  @callback delete_message(external_room_id(), external_message_id(), keyword()) :: provider_result()
  @callback start_typing(external_room_id(), keyword()) :: provider_result()
  @callback fetch_metadata(external_room_id(), keyword()) :: provider_result()
  @callback fetch_thread(external_room_id(), keyword()) :: provider_result()
  @callback fetch_message(external_room_id(), external_message_id(), keyword()) :: provider_result()
  @callback get_user(external_user_id(), keyword()) :: provider_result()
  @callback fetch_subject(external_room_id(), keyword()) :: provider_result()
  @callback get_thread_participants(external_room_id(), keyword()) :: provider_result()
  @callback mark_as_read(external_room_id(), external_message_id(), keyword()) :: provider_result()
  @callback fetch_media(media_reference(), keyword()) :: provider_result()
  @callback add_reaction(external_room_id(), external_message_id(), String.t(), keyword()) :: provider_result()
  @callback remove_reaction(external_room_id(), external_message_id(), String.t(), keyword()) :: provider_result()
  @callback post_ephemeral(external_room_id(), external_user_id(), String.t(), keyword()) :: provider_result()
  @callback post_channel_message(external_room_id(), String.t(), keyword()) :: provider_result()
  @callback stream(external_room_id(), Enumerable.t(), keyword()) :: provider_result()
  @callback open_modal(external_room_id(), Modal.t(), keyword()) :: provider_result()
  @callback load_options(Jido.Signal.t(), keyword()) :: provider_result()
  @callback fetch_messages(external_room_id(), keyword()) :: provider_result()
  @callback fetch_channel_messages(external_room_id(), keyword()) :: provider_result()
  @callback list_threads(external_room_id(), keyword()) :: provider_result()
  @callback open_thread(external_room_id(), external_message_id(), keyword()) :: provider_result()
  @callback open_dm(external_user_id(), keyword()) :: provider_result()
  @callback verify_webhook(WebhookRequest.t(), keyword()) :: :ok | {:error, term()}
  @callback format_webhook_response(term(), keyword()) :: WebhookResponse.t() | map() | {:error, term()}
  @callback listener_child_specs(String.t(), listener_opts()) :: {:ok, [Supervisor.child_spec()]} | {:error, term()}

  @optional_callbacks capabilities: 0,
                      initialize: 1,
                      shutdown: 1,
                      send_message: 3,
                      send_file: 3,
                      post_message: 3,
                      edit_message: 4,
                      delete_message: 3,
                      start_typing: 2,
                      fetch_metadata: 2,
                      fetch_thread: 2,
                      fetch_message: 3,
                      get_user: 2,
                      fetch_subject: 2,
                      get_thread_participants: 2,
                      mark_as_read: 3,
                      fetch_media: 2,
                      add_reaction: 4,
                      remove_reaction: 4,
                      post_ephemeral: 4,
                      post_channel_message: 3,
                      stream: 3,
                      open_modal: 3,
                      load_options: 2,
                      fetch_messages: 2,
                      fetch_channel_messages: 2,
                      list_threads: 2,
                      open_thread: 3,
                      open_dm: 2,
                      verify_webhook: 2,
                      format_webhook_response: 2,
                      listener_child_specs: 2

  @doc "Declares the provider contract and a default channel identity."
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      @behaviour Jido.Chat.Adapter
      @impl true
      def channel_type, do: __MODULE__ |> Module.split() |> Enum.at(-2) |> Macro.underscore() |> String.to_atom()
      defoverridable channel_type: 0
    end
  end

  @doc "Returns the declared operation support with checked native callbacks."
  @spec capabilities(module()) :: capability_matrix()
  def capabilities(adapter) do
    case Jido.Chat.Operations.Capabilities.read(adapter) do
      {:ok, operations} ->
        declared = if function_exported?(adapter, :capabilities, 0), do: adapter.capabilities(), else: %{}
        Map.merge(declared, operations)

      {:error, error} ->
        raise error
    end
  end

  @doc "Checks capability declarations against the exact operation callbacks."
  @spec validate_capabilities(module()) :: :ok | {:error, Jido.Chat.Errors.Contract.t()}
  def validate_capabilities(adapter) do
    case Jido.Chat.Operations.Capabilities.read(adapter) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc "Returns a retained capability matrix value."
  @spec capability_matrix(module()) :: CapabilityMatrix.t()
  def capability_matrix(adapter),
    do: CapabilityMatrix.new(%{adapter_name: adapter_type(adapter), capabilities: capabilities(adapter)})

  @doc "Returns the configured provider channel identity."
  @spec adapter_type(module()) :: atom()
  def adapter_type(adapter), do: adapter.channel_type()

  @doc "Returns the finite core operation fallback list."
  @spec core_fallback_capabilities() :: [atom()]
  def core_fallback_capabilities,
    do: [:post_message, :fetch_metadata, :fetch_thread, :fetch_subject, :post_channel_message, :post_ephemeral, :stream]

  @doc "Renders a retained Markdown builder value."
  @spec render_markdown(term(), keyword()) :: String.t()
  def render_markdown(value, _opts \\ []), do: value |> Markdown.new() |> Markdown.stringify()
  @doc "Renders a retained card builder value."
  @spec render_card(term(), keyword()) :: map()
  def render_card(value, _opts \\ []), do: value |> Card.normalize() |> Card.to_adapter_payload()
  @doc "Renders a retained modal builder value."
  @spec render_modal(term(), keyword()) :: map()
  def render_modal(value, _opts \\ []), do: value |> Modal.new() |> Modal.to_adapter_payload()
  @doc "Renders a finite stream as a domain value, without a provider callback."
  @spec render_stream(Enumerable.t()) :: String.t() | nil
  def render_stream(value), do: Jido.Chat.Markdown.StreamRenderer.render(value)
end
