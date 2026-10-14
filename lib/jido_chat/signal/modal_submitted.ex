defmodule Jido.Chat.Signal.ModalSubmitted do
  @moduledoc """
  Typed fact definition for `jido.chat.modal.submitted`.

  Data uses the protocol version 1 string-key schema. The binding-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Chat.Signal.Definition,
    owner: :chat,
    kind: :fact,
    type: "jido.chat.modal.submitted",
    dataschema: "urn:jido:chat:schema:modal_submitted:1",
    default_source: "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ",
    schema:
      Zoi.map(
        %{
          "item_id" => Zoi.string() |> Zoi.min(1),
          "delivery_id" => Zoi.string() |> Zoi.min(1),
          "room_id" => Zoi.string() |> Zoi.min(1),
          "interaction_id" => Zoi.string() |> Zoi.min(1),
          "view_id" => Zoi.string() |> Zoi.min(1),
          "callback_id" =>
            Zoi.union([
              Zoi.string() |> Zoi.min(1),
              Zoi.null()
            ])
            |> Zoi.optional(),
          "actor_id" =>
            Zoi.union([
              Zoi.string() |> Zoi.min(1),
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
        },
        strict: true
      )
end
