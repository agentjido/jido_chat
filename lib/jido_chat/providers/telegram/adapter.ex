defmodule Jido.Chat.Telegram.Adapter do
  @moduledoc "Stateless Telegram adapter for native Chat request and result Signals."
  use Jido.Chat.Adapter
  alias Jido.Chat.Operations.Builtins
  alias Jido.Chat.Signal.Schemas, as: ChatSchemas
  alias Jido.Chat.Telegram
  alias Jido.Chat.Telegram.{Normalizer, Operations, Signal}

  @definitions Enum.map(
                 [
                   {:send_poll, Telegram.SendPoll, Signal.SendPoll, Signal.Schemas.poll_result()},
                   {:send_photo, Telegram.SendPhoto, Signal.SendPhoto, Signal.Schemas.media_result()},
                   {:send_document, Telegram.SendDocument, Signal.SendDocument, Signal.Schemas.media_result()},
                   {:send_sticker, Telegram.SendSticker, Signal.SendSticker, Signal.Schemas.media_result()},
                   {:send_animation, Telegram.SendAnimation, Signal.SendAnimation, Signal.Schemas.media_result()},
                   {:send_video_note, Telegram.SendVideoNote, Signal.SendVideoNote, Signal.Schemas.media_result()},
                   {:get_file, Telegram.GetFile, Signal.GetFile, Signal.Schemas.file_result()},
                   {:get_me, Telegram.GetMe, Signal.GetMe, Signal.Schemas.user_result()},
                   {:answer_callback_query, Telegram.AnswerCallbackQuery, Signal.AnswerCallbackQuery,
                    Signal.Schemas.callback_result()},
                   {:send_draft, Telegram.SendDraft, Signal.SendDraft, Signal.Schemas.draft_result()},
                   {:fetch_updates, Telegram.FetchUpdates, Signal.FetchUpdates, Signal.Schemas.updates_result()},
                   {:set_webhook, Telegram.SetWebhook, Signal.SetWebhook, ChatSchemas.result(:acknowledgement)},
                   {:get_webhook_info, Telegram.GetWebhookInfo, Signal.GetWebhookInfo, Signal.Schemas.webhook_result()},
                   {:delete_webhook, Telegram.DeleteWebhook, Signal.DeleteWebhook, ChatSchemas.result(:acknowledgement)}
                 ],
                 fn {operation, action, request, result_schema} ->
                   Builtins.define(
                     action,
                     request,
                     result_schema,
                     "telegram_#{operation}",
                     [invoke: {Operations, :invoke, [operation]}],
                     __ENV__
                   )
                 end
               )

  @impl true
  def channel_type, do: :telegram
  @impl true
  def default_transport, do: Jido.Chat.Telegram.Transport.ExGramClient

  @impl true
  def operation_definitions, do: @definitions

  @impl true
  def event_definitions, do: Jido.Chat.Telegram.event_definitions()

  @native [
    :send_message,
    :stream_text,
    :send_file,
    :edit_message,
    :delete_message,
    :start_typing,
    :fetch_metadata,
    :download_file,
    :add_reaction,
    :remove_reaction,
    :open_dm,
    :create_thread
  ]
  @impl true
  def capabilities do
    Map.new(Jido.Chat.Operations.Definitions.all(), fn {_, {_, operation, _, _, _}} ->
      status = if operation in @native, do: :native, else: :unsupported
      {operation, status}
    end)
  end

  @impl true
  def invoke(client, request, opts) do
    case Jido.Chat.Operations.Definitions.lookup(request.type) do
      {_, operation, _, _, _} -> Operations.invoke(operation, client, request, opts)
      _ -> {:error, {:not_attempted, :unsupported}}
    end
  end

  @impl true
  def normalize(client, input, _opts), do: Normalizer.normalize(client, input)
end
