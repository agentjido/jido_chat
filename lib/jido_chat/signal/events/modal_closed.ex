defmodule Jido.Chat.Signal.ModalClosed do
  @moduledoc """
  Typed fact definition for `jido.chat.modal.closed`.

  Data uses the protocol version 1 string-key schema. The client-scoped primary conversation subject. NormalizationFailed can omit subject when the room is unknown.
  """

  use Jido.Signal,
    type: "jido.chat.modal.closed",
    dataschema: "urn:jido:chat:schema:modal_closed:1",
    default_source: "urn:jido:chat:producer:local",
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
            |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end
