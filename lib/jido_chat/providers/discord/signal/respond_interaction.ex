defmodule Jido.Chat.Discord.Signal.RespondInteraction do
  @moduledoc "Interaction response request. The host supplies an Inspect-redacted private Interaction in execution options."
  use Jido.Signal,
    type: "jido.chat.discord.command.respond_interaction",
    dataschema: "urn:jido:chat:discord:respond_interaction:2",
    default_source: "urn:jido:chat:producer:local",
    schema:
      Zoi.map(
        %{
          "client_id" => Jido.Chat.Signal.Schemas.id(),
          "request_id" => Jido.Chat.Signal.Schemas.id(),
          "room_id" => Jido.Chat.Signal.Schemas.id(),
          "interaction_id" => Jido.Chat.Signal.Schemas.id(),
          "response_type" => Zoi.union(Enum.map([4, 5, 6, 7, 9], &Zoi.literal/1)),
          "data" => Zoi.map() |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
