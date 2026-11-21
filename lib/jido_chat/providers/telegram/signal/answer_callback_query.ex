defmodule Jido.Chat.Telegram.Signal.AnswerCallbackQuery do
  @moduledoc "Typed Telegram answer_callback_query request."
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.Signal,
    type: "jido.chat.telegram.command.answer_callback_query",
    dataschema: "urn:jido:chat:telegram:answer_callback_query:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Schemas.request(%{
        "interaction_id" => Schemas.id(),
        "text" => Zoi.string() |> Zoi.max(200) |> Zoi.optional(),
        "show_alert" => Zoi.boolean() |> Zoi.optional()
      })
end
