defmodule Jido.Chat.Discord.Signal.SendRichMessage do
  @moduledoc "Typed Discord message request with embeds and native components."
  use Jido.Signal,
    type: "jido.chat.discord.command.send_rich_message",
    dataschema: "urn:jido:chat:discord:send_rich_message:1",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id(),
          "text" => Zoi.string() |> Zoi.optional(),
          "thread_id" => Jido.Chat.Signal.Schemas.id() |> Zoi.optional(),
          "reply_to_id" => Jido.Chat.Signal.Schemas.id() |> Zoi.optional(),
          "embeds" => Zoi.array(Zoi.map()) |> Zoi.max(10) |> Zoi.optional(),
          "components" => Zoi.array(Zoi.map()) |> Zoi.optional(),
          "tts" => Zoi.boolean() |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
