defmodule Jido.Chat.SentMessage do
  @moduledoc """
  Canonical sent-message handle with follow-up lifecycle operations.
  """

  alias Jido.Chat.{Adapter, Author, Media, Response, Wire}

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              thread_id: Zoi.string(),
              adapter: Zoi.any(),
              external_room_id: Zoi.any() |> Zoi.nullish(),
              response: Zoi.struct(Response),
              text: Zoi.string() |> Zoi.nullish(),
              formatted: Zoi.string() |> Zoi.nullish(),
              raw: Zoi.any() |> Zoi.nullish(),
              author: Zoi.struct(Author) |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{}),
              attachments: Zoi.array(Zoi.struct(Media)) |> Zoi.default([]),
              is_mention: Zoi.boolean() |> Zoi.default(false),
              default_opts: Zoi.any() |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for SentMessage."
  def schema, do: @schema

  @doc "Creates a sent-message handle from normalized adapter response data."
  def new(attrs) when is_map(attrs) do
    attrs
    |> maybe_normalize_response()
    |> normalize_author()
    |> normalize_attachments()
    |> attach_defaults()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Edits the message text and returns an updated sent-message handle."
  @spec edit(t(), String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def edit(%__MODULE__{} = sent, text, opts \\ []) when is_binary(text) do
    with {:ok, response} <-
           Adapter.edit_message(
             sent.adapter,
             sent.external_room_id,
             sent.id,
             text,
             merge_opts(sent, opts)
           ) do
      {:ok,
       %{
         sent
         | id: response.external_message_id || sent.id,
           external_room_id: response.external_room_id || sent.external_room_id,
           response: response,
           text: text,
           formatted: text,
           raw: response.raw
       }}
    end
  end

  @doc "Deletes the message when supported by the adapter."
  @spec delete(t(), keyword()) :: :ok | {:error, term()}
  def delete(%__MODULE__{} = sent, opts \\ []) do
    Adapter.delete_message(sent.adapter, sent.external_room_id, sent.id, merge_opts(sent, opts))
  end

  @doc "Adds a reaction to the message when supported by the adapter."
  @spec add_reaction(t(), String.t(), keyword()) :: :ok | {:error, term()}
  def add_reaction(%__MODULE__{} = sent, emoji, opts \\ []) when is_binary(emoji) do
    Adapter.add_reaction(
      sent.adapter,
      sent.external_room_id,
      sent.id,
      emoji,
      merge_opts(sent, opts)
    )
  end

  @doc "Removes a reaction from the message when supported by the adapter."
  @spec remove_reaction(t(), String.t(), keyword()) :: :ok | {:error, term()}
  def remove_reaction(%__MODULE__{} = sent, emoji, opts \\ []) when is_binary(emoji) do
    Adapter.remove_reaction(
      sent.adapter,
      sent.external_room_id,
      sent.id,
      emoji,
      merge_opts(sent, opts)
    )
  end

  @doc "Serializes the sent message into a plain map with type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = sent) do
    response =
      sent.response
      |> Map.from_struct()
      |> Wire.to_plain()

    sent
    |> Map.from_struct()
    |> Map.put(:adapter, Wire.encode_module(sent.adapter))
    |> Map.put(:response, response)
    |> Wire.to_plain()
    |> Map.put("__type__", "sent_message")
  end

  @doc "Builds a sent message from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    adapter = map[:adapter] || map["adapter"]

    map
    |> Map.drop(["__type__", :__type__])
    |> Map.delete("adapter")
    |> Map.put(:adapter, Wire.decode_module(adapter))
    |> new()
  end

  defp maybe_normalize_response(%{response: %Response{}} = attrs), do: attrs

  defp maybe_normalize_response(%{response: response} = attrs) when is_map(response),
    do: attrs |> Map.delete("response") |> Map.put(:response, Response.new(response))

  defp maybe_normalize_response(%{"response" => %Response{} = response} = attrs),
    do: attrs |> Map.delete("response") |> Map.put(:response, response)

  defp maybe_normalize_response(%{"response" => response} = attrs) when is_map(response),
    do: attrs |> Map.delete("response") |> Map.put(:response, Response.new(response))

  defp maybe_normalize_response(attrs), do: attrs

  defp normalize_author(%{author: %Author{}} = attrs), do: attrs

  defp normalize_author(%{author: author} = attrs) when is_map(author),
    do: Map.put(attrs, :author, Author.new(author))

  defp normalize_author(attrs), do: attrs

  defp normalize_attachments(attrs) do
    attachments = attrs[:attachments] || attrs["attachments"] || []

    normalized =
      Enum.map(attachments, fn
        %Media{} = media -> media
        map when is_map(map) -> Media.new(map)
        other -> other
      end)

    Map.put(attrs, :attachments, normalized)
  end

  defp attach_defaults(%{response: %Response{} = response} = attrs) do
    attrs
    |> Map.put_new(:id, response.external_message_id || Jido.Chat.ID.generate!())
    |> Map.put_new(:thread_id, thread_id(attrs, response))
    |> Map.put_new(:external_room_id, response.external_room_id)
    |> Map.put_new(:text, attrs[:text] || attrs["text"])
    |> Map.put_new(
      :formatted,
      attrs[:formatted] || attrs["formatted"] || attrs[:text] || attrs["text"]
    )
    |> Map.put_new(:raw, attrs[:raw] || attrs["raw"] || response.raw)
    |> Map.put_new(:metadata, attrs[:metadata] || attrs["metadata"] || response.metadata || %{})
    |> Map.put_new(:attachments, [])
    |> Map.put_new(:is_mention, attrs[:is_mention] || attrs["is_mention"] || false)
    |> Map.put_new(:default_opts, [])
  end

  defp thread_id(attrs, response) do
    attrs[:thread_id] || attrs["thread_id"] ||
      "#{response.channel_type || :unknown}:#{response.external_room_id || "unknown"}"
  end

  defp merge_opts(%__MODULE__{default_opts: defaults}, opts)
       when is_list(defaults) and is_list(opts),
       do: Keyword.merge(defaults, opts)

  defp merge_opts(_sent, opts), do: opts
end
