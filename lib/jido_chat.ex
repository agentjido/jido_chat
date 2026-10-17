defmodule Jido.Chat do
  @moduledoc """
  Public typed Signal boundary and retained domain builders.

  `jido_chat` owns canonical chat types, adapter contracts, typed handles, and
  deterministic fallback behavior. It does not define the supervised runtime or
  process tree for production messaging systems; that responsibility belongs in
  `jido_messaging`.
  """

  @doc "Returns the explicit public Signal definition list for this domain."
  @spec signal_definitions() :: [module()]
  def signal_definitions do
    [
      Jido.Chat.Signal.SendMessage,
      Jido.Chat.Signal.SendFile,
      Jido.Chat.Signal.PostMessage,
      Jido.Chat.Signal.EditMessage,
      Jido.Chat.Signal.DeleteMessage,
      Jido.Chat.Signal.StartTyping,
      Jido.Chat.Signal.FetchMetadata,
      Jido.Chat.Signal.FetchThread,
      Jido.Chat.Signal.FetchMessage,
      Jido.Chat.Signal.GetUser,
      Jido.Chat.Signal.FetchSubject,
      Jido.Chat.Signal.GetThreadParticipants,
      Jido.Chat.Signal.MarkAsRead,
      Jido.Chat.Signal.FetchMedia,
      Jido.Chat.Signal.AddReaction,
      Jido.Chat.Signal.RemoveReaction,
      Jido.Chat.Signal.PostEphemeral,
      Jido.Chat.Signal.PostChannelMessage,
      Jido.Chat.Signal.Stream,
      Jido.Chat.Signal.OpenModal,
      Jido.Chat.Signal.LoadOptions,
      Jido.Chat.Signal.FetchMessages,
      Jido.Chat.Signal.FetchChannelMessages,
      Jido.Chat.Signal.ListThreads,
      Jido.Chat.Signal.OpenThread,
      Jido.Chat.Signal.OpenDm,
      Jido.Chat.Signal.MessageReceived,
      Jido.Chat.Signal.MessageUpdated,
      Jido.Chat.Signal.MessageDeleted,
      Jido.Chat.Signal.ReactionAdded,
      Jido.Chat.Signal.ReactionRemoved,
      Jido.Chat.Signal.ActionReceived,
      Jido.Chat.Signal.ModalSubmitted,
      Jido.Chat.Signal.ModalClosed,
      Jido.Chat.Signal.OptionsRequested,
      Jido.Chat.Signal.SlashCommandReceived,
      Jido.Chat.Signal.AssistantThreadStarted,
      Jido.Chat.Signal.AssistantContextChanged,
      Jido.Chat.Signal.MembershipChanged,
      Jido.Chat.Signal.ThreadStarted,
      Jido.Chat.Signal.ReceiptReceived,
      Jido.Chat.Signal.NormalizationFailed,
      Jido.Chat.Signal.OperationCompleted,
      Jido.Chat.Signal.OperationFailed,
      Jido.Chat.Signal.ThreadChanged
    ]
  end

  @doc "Creates a protocol version 1 binding before provider listeners start."
  @spec bind(module(), keyword()) :: {:ok, Jido.Chat.Binding.t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def bind(adapter, opts), do: Jido.Chat.Binding.new(adapter, opts)

  @doc "Stores one private call-local value and returns a scoped public resource reference."
  @spec put_resource(Jido.Chat.Binding.t(), String.t(), term(), keyword()) ::
          {:ok, map()} | {:error, Jido.Chat.Errors.Contract.t()}
  def put_resource(binding, kind, value, opts \\ []), do: Jido.Chat.Resources.put(binding, kind, value, opts)

  @doc "Resolves a scoped resource for its call owner."
  @spec resolve_resource(Jido.Chat.Binding.t(), map()) :: {:ok, term()} | {:error, Jido.Chat.Errors.Contract.t()}
  def resolve_resource(binding, ref), do: Jido.Chat.Resources.resolve(binding, ref)

  @doc "Cancels a scoped resource for its call owner."
  @spec cancel_resource(Jido.Chat.Binding.t(), map()) :: :ok | {:error, Jido.Chat.Errors.Contract.t()}
  def cancel_resource(binding, ref), do: Jido.Chat.Resources.cancel(binding, ref)

  @doc "Normalizes a private provider request into one completely validated delivery."
  @spec normalize_event(Jido.Chat.Binding.t(), term()) ::
          {:ok, Jido.Chat.Delivery.t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def normalize_event(%Jido.Chat.Binding{} = binding, provider_request) do
    case binding.adapter.normalize_event(binding, provider_request) do
      {:ok, %Jido.Chat.Delivery{} = delivery} -> Jido.Chat.Delivery.validate(binding, delivery)
      {:error, %Jido.Chat.Errors.Contract{}} = error -> error
      _ -> Jido.Chat.Signal.Policy.error(:invalid_delivery)
    end
  rescue
    _ -> Jido.Chat.Signal.Policy.error(:invalid_delivery)
  catch
    _, _ -> Jido.Chat.Signal.Policy.error(:invalid_delivery)
  end

  def normalize_event(_binding, _provider_request), do: Jido.Chat.Signal.Policy.error(:invalid_binding)

  @doc "Executes one validated typed request through the configured provider boundary."
  @spec execute(Jido.Chat.Binding.t(), Jido.Signal.t()) ::
          {:ok, Jido.Signal.t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def execute(binding, request), do: Jido.Chat.Operations.Executor.execute(binding, request)

  @doc "Creates a retained domain message record."
  @spec message(map()) :: Jido.Chat.Message.t()
  def message(attrs), do: Jido.Chat.Message.new(attrs)

  @doc "Creates a retained room record."
  @spec new_room(map()) :: Jido.Chat.Room.t()
  def new_room(attrs), do: Jido.Chat.Room.new(attrs)

  @doc "Creates a retained participant record."
  @spec new_participant(map()) :: Jido.Chat.Participant.t()
  def new_participant(attrs), do: Jido.Chat.Participant.new(attrs)

  @doc "Creates a text content value."
  @spec text(String.t()) :: Jido.Chat.Content.Text.t()
  def text(value), do: Jido.Chat.Content.Text.new(value)

  @doc "Renders a portable emoji value."
  @spec emoji(String.t(), keyword()) :: String.t()
  def emoji(value, opts \\ []), do: Jido.Chat.Emoji.render(value, opts)
end
