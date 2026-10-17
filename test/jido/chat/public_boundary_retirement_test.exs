defmodule Jido.Chat.PublicBoundaryRetirementTest do
  use ExUnit.Case, async: true

  @retired ~w(ActionEvent AssistantContextChangedEvent AssistantThreadStartedEvent Incoming Response SentMessage EventEnvelope IngressResult EventNormalizer EventRouter HandlerDispatch WebhookPipeline MessageUpdatedEvent MessageDeletedEvent ReactionEvent ModalSubmitEvent ModalCloseEvent ModalResult ModalResponse OptionsLoadEvent OptionsLoadResult OptionsLoadError SlashCommandEvent MessageLifecycleEvent MessageContext Serialization Concurrency StateAdapter StateAdapters.Memory AdapterRegistry)

  test "the new major line has no old public event/DTO wrappers or duplicate router" do
    for name <- @retired do
      module = Module.concat(["Jido.Chat", name])
      refute Code.ensure_loaded?(module), "retired #{name} must not remain in the release line"
    end

    retired_calls = [
      :new,
      :process_message,
      :process_event,
      :route_event,
      :route_request,
      :handle_webhook,
      :handle_webhook_request,
      :on_new_mention,
      :on_new_message,
      :open_dm,
      :open_thread
    ]

    refute Enum.any?(Jido.Chat.__info__(:functions), fn {name, _} -> name in retired_calls end)

    for {_type, {_module, operation, _fields, _shape, _schema}} <- Jido.Chat.Operations.Definitions.all() do
      refute Enum.any?(Jido.Chat.Adapter.__info__(:functions), fn {name, _} -> name == operation end)
    end
  end
end
