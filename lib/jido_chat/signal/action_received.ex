defmodule Jido.Chat.Signal.ActionReceived do
  @moduledoc """
  Typed fact definition for `jido.chat.action.received`.

  Data uses the protocol version 1 string-key schema. The binding-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.action.received",
    dataschema: "urn:jido:chat:schema:action_received:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
    schema:
      Zoi.map(
        %{
          "item_id" => Zoi.string() |> Zoi.min(1),
          "delivery_id" => Zoi.string() |> Zoi.min(1),
          "room_id" => Zoi.string() |> Zoi.min(1),
          "interaction_id" => Zoi.string() |> Zoi.min(1),
          "action_id" => Zoi.string() |> Zoi.min(1),
          "actor_id" =>
            Zoi.union([
              Zoi.string() |> Zoi.min(1),
              Zoi.null()
            ])
            |> Zoi.optional(),
          "message_id" =>
            Zoi.union([
              Zoi.string() |> Zoi.min(1),
              Zoi.null()
            ])
            |> Zoi.optional(),
          "thread_id" =>
            Zoi.union([
              Zoi.string() |> Zoi.min(1),
              Zoi.null()
            ])
            |> Zoi.optional(),
          "value" =>
            Zoi.union([
              Zoi.string(),
              Zoi.null()
            ])
            |> Zoi.optional(),
          "values" =>
            Zoi.map(
              %{},
              unrecognized_keys:
                {:preserve,
                 {Zoi.string(),
                  Zoi.union([
                    Zoi.string(),
                    Zoi.array(Zoi.string()),
                    Zoi.boolean(),
                    Zoi.number(),
                    Zoi.null()
                  ])}}
            )
            |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
