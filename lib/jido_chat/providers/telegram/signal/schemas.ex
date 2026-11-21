defmodule Jido.Chat.Telegram.Signal.Schemas do
  @moduledoc false

  @doc false
  def id, do: Zoi.string() |> Zoi.min(1)
  @doc false
  def object(fields), do: Zoi.map(fields, unrecognized_keys: :error)

  @doc false
  def request(fields),
    do: object(Map.merge(%{"client_id" => id(), "request_id" => id()}, fields))

  @doc false
  def reference, do: Jido.Chat.Signal.Schemas.reference()
  @doc false
  def source, do: Jido.Chat.Signal.Schemas.file_source()

  @doc false
  def media_request(caption? \\ true) do
    fields = %{
      "room_id" => id(),
      "source" => source(),
      "thread_id" => id() |> Zoi.optional(),
      "reply_to_id" => id() |> Zoi.optional(),
      "keyboard" => Jido.Chat.Signal.Schemas.keyboard() |> Zoi.optional()
    }

    fields =
      if caption?,
        do:
          Map.merge(fields, %{
            "caption" => Zoi.string() |> Zoi.optional(),
            "format" => Zoi.enum(["plain", "markdown", "html"]) |> Zoi.optional()
          }),
        else: fields

    request(fields)
  end

  @doc false
  def numeric_id, do: id() |> Zoi.refine({__MODULE__, :valid_numeric_id, []})

  @doc false
  def valid_numeric_id(value, _opts) do
    case Integer.parse(value) do
      {_, ""} -> :ok
      _ -> {:error, "expected a numeric Telegram chat ID"}
    end
  end

  @doc false
  def media_result,
    do: object(%{"id" => id(), "room_id" => id(), "resource_ref" => reference()})

  @doc false
  def poll_result,
    do: object(%{"id" => id(), "room_id" => id(), "poll_id" => id()})

  @doc false
  def file_result do
    object(%{
      "resource_ref" => reference(),
      "file_path" => id() |> Zoi.refine({__MODULE__, :file_path, []}),
      "size" => Zoi.integer() |> Zoi.min(0) |> Zoi.optional()
    })
  end

  @doc false
  def file_path(path, _opts) do
    if Regex.match?(~r/^[a-zA-Z0-9_\/.\-]+$/, path) and not Enum.any?(String.split(path, "/"), &(&1 in ["", ".", ".."])),
      do: :ok,
      else: {:error, "invalid Telegram file path"}
  end

  @doc false
  def webhook_result do
    object(%{
      "url" => Zoi.string(),
      "pending_update_count" => Zoi.integer() |> Zoi.min(0),
      "has_custom_certificate" => Zoi.boolean()
    })
  end

  @doc false
  def user_result do
    object(%{
      "id" => id(),
      "username" => Zoi.string() |> Zoi.optional(),
      "display_name" => Zoi.string() |> Zoi.optional(),
      "is_bot" => Zoi.boolean()
    })
  end

  @doc false
  def callback_result, do: object(%{"answered" => Zoi.boolean(), "interaction_id" => id()})
  @doc false
  def draft_result, do: object(%{"acknowledged" => Zoi.boolean(), "draft_id" => Zoi.integer() |> Zoi.min(1)})

  @doc false
  def updates_result do
    object(%{
      "delivery_id" => id(),
      "signals" => Zoi.array(Zoi.map()),
      "next_offset" => Zoi.integer() |> Zoi.min(0) |> Zoi.nullish()
    })
  end
end
