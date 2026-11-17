defmodule Jido.Chat.Signal.Schemas do
  @moduledoc false
  @doc false
  def id, do: Jido.Joi.string() |> Jido.Joi.min(1)
  @doc false
  def optional_id, do: id() |> Jido.Joi.nullable() |> Jido.Joi.optional()
  @doc false
  def object(fields), do: Jido.Joi.map(fields, unrecognized_keys: :error)

  @doc false
  def modal, do: rendering_schema(Jido.Chat.Modal, "modal")

  @doc false
  def card, do: rendering_schema(Jido.Chat.Card, "card")

  defp rendering_schema(module, marker) do
    module.signal_fields()
    |> Map.put("__type__", Jido.Joi.literal(marker) |> Jido.Joi.optional())
    |> object()
    |> Jido.Joi.refine({__MODULE__, :valid_rendering, [module, marker]})
  end

  @doc false
  def valid_rendering(value, module, marker, _opts) do
    with :ok <- valid_rendering_marker(value, marker) do
      value
      |> Map.delete("__type__")
      |> module.new()

      :ok
    end
  rescue
    _ -> {:error, "expected a valid #{inspect(module)} value"}
  end

  defp valid_rendering_marker(value, marker) do
    case Map.get(value, "__type__") do
      value when value in [nil, marker] -> :ok
      _value -> {:error, "expected rendering type #{inspect(marker)}"}
    end
  end

  @doc false
  def reference do
    object(%{"id" => id(), "client_id" => id(), "kind" => Jido.Joi.enum(["file", "media", "url"])})
  end

  @doc false
  def file_source do
    Jido.Joi.union([
      reference(),
      object(%{
        "content_base64" =>
          Jido.Joi.string() |> Jido.Joi.max(240_000) |> Jido.Joi.refine({__MODULE__, :valid_base64, []}),
        "filename" => id()
      })
    ])
  end

  @doc false
  def valid_base64(value, _opts) do
    case Base.decode64(value) do
      {:ok, bytes} when byte_size(bytes) > 0 -> :ok
      _ -> {:error, "expected non-empty base64 file content"}
    end
  end

  @doc false
  def keyboard do
    button =
      Jido.Joi.union([
        object(%{"text" => id(), "value" => id() |> Jido.Joi.refine({__MODULE__, :callback_value, []})}),
        object(%{"text" => id(), "url" => id()})
      ])

    object(%{
      "rows" => Jido.Joi.array(Jido.Joi.array(button) |> Jido.Joi.min(1) |> Jido.Joi.max(8)) |> Jido.Joi.max(100)
    })
    |> Jido.Joi.refine({__MODULE__, :keyboard_size, []})
  end

  @doc false
  def callback_value(value, _opts) do
    if byte_size(value) <= 64, do: :ok, else: {:error, "button value exceeds 64 bytes"}
  end

  @doc false
  def keyboard_size(%{"rows" => rows}, _opts) do
    if Enum.sum(Enum.map(rows, &length/1)) <= 100, do: :ok, else: {:error, "keyboard exceeds 100 buttons"}
  end

  @doc false
  def actor do
    object(%{
      "id" => id(),
      "username" => Jido.Joi.string() |> Jido.Joi.optional(),
      "display_name" => Jido.Joi.string() |> Jido.Joi.optional(),
      "is_bot" => Jido.Joi.boolean() |> Jido.Joi.optional(),
      "is_self" => Jido.Joi.boolean() |> Jido.Joi.optional()
    })
  end

  @doc false
  def media do
    object(%{
      "kind" => Jido.Joi.enum(["image", "audio", "video", "file"]),
      "resource_ref" => reference(),
      "name" => Jido.Joi.string() |> Jido.Joi.optional(),
      "media_type" => Jido.Joi.string() |> Jido.Joi.optional(),
      "caption" => Jido.Joi.string() |> Jido.Joi.optional(),
      "width" => Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.optional(),
      "height" => Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.optional(),
      "duration" => Jido.Joi.number() |> Jido.Joi.min(0) |> Jido.Joi.optional(),
      "metadata" => Jido.Joi.map() |> Jido.Joi.optional()
    })
  end

  @doc false
  def completion(operation, result) do
    object(%{
      "client_id" => id(),
      "request_id" => id(),
      "operation" => Jido.Joi.literal(operation),
      "result" => result
    })
  end

  @doc false
  def result(:message) do
    object(%{
      "id" => id(),
      "room_id" => id(),
      "text" => Jido.Joi.string() |> Jido.Joi.optional(),
      "sender" => actor() |> Jido.Joi.optional(),
      "thread_id" => optional_id(),
      "reply_to_id" => optional_id(),
      "media" => Jido.Joi.array(media()) |> Jido.Joi.optional(),
      "timestamp" => Jido.Joi.string() |> Jido.Joi.optional(),
      "status" => Jido.Joi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Jido.Joi.optional(),
      "role" => Jido.Joi.enum(["user", "assistant", "system", "tool"]) |> Jido.Joi.optional()
    })
  end

  @doc false
  def result(:acknowledgement), do: object(%{"acknowledged" => Jido.Joi.boolean()})

  @doc false
  def result(:conversation),
    do:
      object(%{
        "id" => id(),
        "name" => Jido.Joi.string() |> Jido.Joi.optional(),
        "kind" => Jido.Joi.enum(["direct", "group", "channel", "thread", "unknown"]),
        "topic" => Jido.Joi.string() |> Jido.Joi.optional()
      })

  @doc false
  def result(:thread),
    do:
      object(%{
        "id" => id(),
        "room_id" => id(),
        "parent_message_id" => optional_id(),
        "name" => Jido.Joi.string() |> Jido.Joi.optional(),
        "delivery_room_ref" => optional_id()
      })

  @doc false
  def result(:created_thread) do
    object(%{
      "id" => id(),
      "room_id" => id(),
      "name" => id(),
      "parent_message_id" => optional_id(),
      "delivery_room_ref" => optional_id()
    })
  end

  @doc false
  def result(:user), do: actor()

  @doc false
  def result(:subject),
    do:
      object(%{
        "id" => id(),
        "room_id" => id(),
        "kind" => Jido.Joi.enum(["conversation", "thread", "message"]),
        "title" => Jido.Joi.string() |> Jido.Joi.optional()
      })

  @doc false
  def result(:participants),
    do:
      object(%{
        "participants" => Jido.Joi.array(actor()),
        "complete" => Jido.Joi.boolean(),
        "scope" => Jido.Joi.enum(["observed", "all"]),
        "next_cursor" => optional_id()
      })

  @doc false
  def result(:resource),
    do: object(%{"content_base64" => Jido.Joi.string() |> Jido.Joi.refine({__MODULE__, :download_base64, []})})

  @doc false
  def result(:modal), do: object(%{"opened" => Jido.Joi.boolean(), "id" => id() |> Jido.Joi.optional()})

  @doc false
  def result(:options),
    do:
      object(%{
        "options" => Jido.Joi.array(option()),
        "option_groups" =>
          Jido.Joi.array(object(%{"label" => Jido.Joi.string(), "options" => Jido.Joi.array(option())}))
          |> Jido.Joi.optional(),
        "complete" => Jido.Joi.boolean()
      })

  @doc false
  def result(:message_page), do: page("messages", result(:message))
  @doc false
  def result(:thread_page), do: page("threads", result(:thread))

  @doc false
  def download_base64(value, _opts) do
    case Base.decode64(value) do
      {:ok, _bytes} -> :ok
      _ -> {:error, "expected base64 file content"}
    end
  end

  defp page(key, item),
    do: object(%{key => Jido.Joi.array(item), "next_cursor" => optional_id(), "complete" => Jido.Joi.boolean()})

  defp option,
    do:
      object(%{
        "label" => Jido.Joi.string(),
        "value" => Jido.Joi.string(),
        "description" => Jido.Joi.string() |> Jido.Joi.optional(),
        "url" => Jido.Joi.string() |> Jido.Joi.optional()
      })
end
