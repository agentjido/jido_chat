defmodule Jido.Chat.Telegram.Signal.SendPoll do
  @moduledoc "Typed Telegram poll request. This definition is outside the core Chat catalog."
  use Jido.Signal,
    type: "jido.chat.telegram.command.send_poll",
    dataschema: "urn:jido:chat:telegram:send_poll:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Zoi.string() |> Zoi.min(1),
          "request_id" => Zoi.string() |> Zoi.min(1),
          "room_id" => Zoi.string() |> Zoi.min(1),
          "question" => Zoi.string() |> Zoi.min(1) |> Zoi.max(300),
          "options" => Zoi.array(Zoi.string() |> Zoi.min(1) |> Zoi.max(100)) |> Zoi.min(2) |> Zoi.max(12),
          "thread_id" => Zoi.string() |> Zoi.min(1) |> Zoi.optional(),
          "is_anonymous" => Zoi.boolean() |> Zoi.optional(),
          "reply_to_id" => Jido.Chat.Signal.Schemas.id() |> Zoi.optional(),
          "keyboard" => Jido.Chat.Signal.Schemas.keyboard() |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
