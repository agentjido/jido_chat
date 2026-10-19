defmodule Jido.Chat.Signal.Schemas do
  @moduledoc false
  @doc false
  def id, do: Zoi.string() |> Zoi.min(1)
  @doc false
  def optional_id, do: id() |> Zoi.nullish()
  @doc false
  def object(fields), do: Zoi.map(fields, unrecognized_keys: :error)

  @doc false
  def modal, do: rendering_schema(Jido.Chat.Modal, "modal")

  @doc false
  def card, do: rendering_schema(Jido.Chat.Card, "card")

  defp rendering_schema(module, marker) do
    fields =
      Map.new(module.schema().fields, fn
        {key, %Zoi.Types.Array{inner: %Zoi.Types.Struct{}} = schema} ->
          {Atom.to_string(key), %{schema | inner: Zoi.map()}}

        {key, schema} ->
          {Atom.to_string(key), schema}
      end)

    fields
    |> Map.put("__type__", Zoi.literal(marker) |> Zoi.optional())
    |> object()
    |> Zoi.refine({__MODULE__, :valid_rendering, [module]})
  end

  @doc false
  def valid_rendering(value, module, _opts) do
    module.new(value)
    :ok
  rescue
    _ -> {:error, "expected a valid #{inspect(module)} value"}
  end

  @doc false
  def reference do
    object(%{"id" => id(), "client_id" => id(), "kind" => Zoi.enum(["file", "media", "url"])})
  end

  @doc false
  def file_source do
    Zoi.union([
      reference(),
      object(%{
        "content_base64" => Zoi.string() |> Zoi.max(240_000) |> Zoi.refine({__MODULE__, :valid_base64, []}),
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
      Zoi.union([
        object(%{"text" => id(), "value" => id() |> Zoi.refine({__MODULE__, :callback_value, []})}),
        object(%{"text" => id(), "url" => id()})
      ])

    object(%{"rows" => Zoi.array(Zoi.array(button) |> Zoi.min(1) |> Zoi.max(8)) |> Zoi.max(100)})
    |> Zoi.refine({__MODULE__, :keyboard_size, []})
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
      "username" => Zoi.string() |> Zoi.optional(),
      "display_name" => Zoi.string() |> Zoi.optional(),
      "is_bot" => Zoi.boolean() |> Zoi.optional(),
      "is_self" => Zoi.boolean() |> Zoi.optional()
    })
  end

  @doc false
  def media do
    object(%{
      "kind" => Zoi.enum(["image", "audio", "video", "file"]),
      "resource_ref" => reference(),
      "name" => Zoi.string() |> Zoi.optional(),
      "media_type" => Zoi.string() |> Zoi.optional(),
      "caption" => Zoi.string() |> Zoi.optional(),
      "width" => Zoi.integer() |> Zoi.min(0) |> Zoi.optional(),
      "height" => Zoi.integer() |> Zoi.min(0) |> Zoi.optional(),
      "duration" => Zoi.number() |> Zoi.min(0) |> Zoi.optional(),
      "metadata" => Zoi.map() |> Zoi.optional()
    })
  end

  @doc false
  def completion(operation, result) do
    object(%{
      "client_id" => id(),
      "request_id" => id(),
      "operation" => Zoi.literal(operation),
      "result" => result
    })
  end

  @doc false
  def result(:message) do
    object(%{
      "id" => id(),
      "room_id" => id(),
      "text" => Zoi.string() |> Zoi.optional(),
      "sender" => actor() |> Zoi.optional(),
      "thread_id" => optional_id(),
      "reply_to_id" => optional_id(),
      "media" => Zoi.array(media()) |> Zoi.optional(),
      "timestamp" => Zoi.string() |> Zoi.optional(),
      "status" => Zoi.enum(["sent", "received", "updated", "deleted", "pending", "failed"]) |> Zoi.optional(),
      "role" => Zoi.enum(["user", "assistant", "system", "tool"]) |> Zoi.optional()
    })
  end

  @doc false
  def result(:acknowledgement), do: object(%{"acknowledged" => Zoi.boolean()})

  @doc false
  def result(:conversation),
    do:
      object(%{
        "id" => id(),
        "name" => Zoi.string() |> Zoi.optional(),
        "kind" => Zoi.enum(["direct", "group", "channel", "thread", "unknown"]),
        "topic" => Zoi.string() |> Zoi.optional()
      })

  @doc false
  def result(:thread),
    do:
      object(%{
        "id" => id(),
        "room_id" => id(),
        "parent_message_id" => optional_id(),
        "name" => Zoi.string() |> Zoi.optional(),
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
        "kind" => Zoi.enum(["conversation", "thread", "message"]),
        "title" => Zoi.string() |> Zoi.optional()
      })

  @doc false
  def result(:participants),
    do:
      object(%{
        "participants" => Zoi.array(actor()),
        "complete" => Zoi.boolean(),
        "scope" => Zoi.enum(["observed", "all"]),
        "next_cursor" => optional_id()
      })

  @doc false
  def result(:resource),
    do: object(%{"content_base64" => Zoi.string() |> Zoi.refine({__MODULE__, :download_base64, []})})

  @doc false
  def result(:modal), do: object(%{"opened" => Zoi.boolean(), "id" => id() |> Zoi.optional()})

  @doc false
  def result(:options),
    do:
      object(%{
        "options" => Zoi.array(option()),
        "option_groups" =>
          Zoi.array(object(%{"label" => Zoi.string(), "options" => Zoi.array(option())})) |> Zoi.optional(),
        "complete" => Zoi.boolean()
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
    do: object(%{key => Zoi.array(item), "next_cursor" => optional_id(), "complete" => Zoi.boolean()})

  defp option,
    do:
      object(%{
        "label" => Zoi.string(),
        "value" => Zoi.string(),
        "description" => Zoi.string() |> Zoi.optional(),
        "url" => Zoi.string() |> Zoi.optional()
      })
end
