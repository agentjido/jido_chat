defmodule Jido.Chat.SentMessage do
  @moduledoc """
  Canonical sent-message handle with follow-up lifecycle operations.
  """

  alias Jido.Chat.{Adapter, Attachment, Author, Emoji, FileUpload, Postable, PostPayload, Response, Wire}

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.any(),
              thread_id: Zoi.string(),
              adapter: Zoi.any(),
              external_room_id: Zoi.any() |> Zoi.nullish(),
              response: Zoi.struct(Response),
              text: Zoi.string() |> Zoi.nullish(),
              formatted: Zoi.string() |> Zoi.nullish(),
              raw: Zoi.any() |> Zoi.nullish(),
              author: Zoi.struct(Author) |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{}),
              attachments: Zoi.array(Zoi.struct(Attachment)) |> Zoi.default([]),
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

  @doc """
  Creates a sent-message handle from normalized adapter response data.

  A response metadata attachment snapshot (`:attachments` or `"attachments"`)
  takes precedence over supplied attachments, including an explicit empty list.
  Without a snapshot, supplied attachments are preserved. The snapshot describes
  this handle's message; attachments on other posts belong in delivery metadata.
  """
  def new(attrs) when is_map(attrs) do
    attrs
    |> maybe_normalize_response()
    |> normalize_author()
    |> normalize_attachments()
    |> attach_defaults()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc """
  Edits the existing message using the canonical outbound payload contract.

  Attachment edits require the adapter to declare `edit_attachments: :native`.
  Upload candidates are normalized into `FileUpload` values and passed in `:files`;
  the adapter owns upload limits and delivery. Adapters receive `:previous_metadata`
  from the handle and its latest response for identity-aware reconciliation of
  incomplete responses. Delivery response values take precedence over handle metadata.
  Response metadata may include `:attachments` (or `"attachments"`) as an
  authoritative list, including an empty list to confirm removal. When absent,
  text-only edits retain attachments and upload edits use the outbound payload.
  """
  @spec edit(t(), String.t() | Postable.t() | map(), keyword()) :: {:ok, t()} | {:error, term()}
  def edit(message, input, opts \\ [])

  def edit(%__MODULE__{} = sent, text, opts) when is_binary(text) do
    text
    |> PostPayload.text()
    |> then(&edit_payload(sent, &1, opts))
  end

  def edit(%__MODULE__{} = sent, %Postable{} = postable, opts) do
    postable
    |> Postable.to_payload()
    |> then(&edit_payload(sent, &1, opts))
  end

  def edit(%__MODULE__{} = sent, postable_map, opts) when is_map(postable_map) do
    postable_map
    |> Postable.new()
    |> Postable.to_payload()
    |> then(&edit_payload(sent, &1, opts))
  rescue
    _ -> {:error, :invalid_postable}
  end

  @doc "Deletes the message when supported by the adapter."
  @spec delete(t(), keyword()) :: :ok | {:error, term()}
  def delete(%__MODULE__{} = sent, opts \\ []) do
    Adapter.delete_message(sent.adapter, sent.external_room_id, sent.id, merge_opts(sent, opts))
  end

  @doc "Adds a reaction to the message when supported by the adapter."
  @spec add_reaction(t(), String.t() | atom(), keyword()) :: :ok | {:error, term()}
  def add_reaction(%__MODULE__{} = sent, emoji, opts \\ []) do
    emoji = Emoji.render(emoji, custom: opts[:custom_emoji])

    Adapter.add_reaction(
      sent.adapter,
      sent.external_room_id,
      sent.id,
      emoji,
      merge_opts(sent, opts)
    )
  end

  @doc "Removes a reaction from the message when supported by the adapter."
  @spec remove_reaction(t(), String.t() | atom(), keyword()) :: :ok | {:error, term()}
  def remove_reaction(%__MODULE__{} = sent, emoji, opts \\ []) do
    emoji = Emoji.render(emoji, custom: opts[:custom_emoji])

    Adapter.remove_reaction(
      sent.adapter,
      sent.external_room_id,
      sent.id,
      emoji,
      merge_opts(sent, opts)
    )
  end

  @doc "Marks this provider message as read. Repeated calls are safe when the adapter is compliant."
  @spec mark_as_read(t(), keyword()) :: :ok | {:error, term()}
  def mark_as_read(%__MODULE__{} = sent, opts \\ []) do
    case sent.response.external_message_id do
      message_id when is_binary(message_id) ->
        if String.trim(message_id) == "" do
          {:error, :missing_external_message_id}
        else
          Adapter.mark_as_read(
            sent.adapter,
            sent.external_room_id,
            message_id,
            merge_opts(sent, opts)
          )
        end

      message_id when is_integer(message_id) ->
        Adapter.mark_as_read(
          sent.adapter,
          sent.external_room_id,
          message_id,
          merge_opts(sent, opts)
        )

      _ ->
        {:error, :missing_external_message_id}
    end
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
    fallback = attrs[:attachments] || attrs["attachments"] || []
    response = attrs[:response] || attrs["response"]
    metadata = if match?(%Response{}, response), do: response.metadata, else: %{}
    attachments = response_attachments(metadata, fallback)

    normalized =
      Enum.map(attachments, fn
        %Attachment{} = attachment -> attachment
        attachment -> Attachment.normalize(attachment)
      end)

    attrs
    |> Map.delete("attachments")
    |> Map.put(:attachments, normalized)
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

  defp edit_payload(%__MODULE__{} = sent, %PostPayload{} = payload, opts) do
    upload_candidates = PostPayload.upload_candidates(payload)
    text = PostPayload.display_text(payload)

    cond do
      payload.kind == :stream ->
        {:error, :edit_stream_unsupported}

      upload_candidates != [] and
          Map.get(Adapter.capabilities(sent.adapter), :edit_attachments) != :native ->
        {:error, :edit_attachments_unsupported}

      true ->
        with {:ok, response} <-
               Adapter.edit_message(
                 sent.adapter,
                 sent.external_room_id,
                 sent.id,
                 text || "",
                 edit_opts(sent, opts, upload_candidates)
               ) do
          {:ok,
           %{
             sent
             | id: response.external_message_id || sent.id,
               external_room_id: response.external_room_id || sent.external_room_id,
               response: response,
               text: text,
               formatted: payload.formatted || text,
               raw: payload.raw || response.raw,
               metadata:
                 sent |> previous_metadata() |> merge_metadata(payload.metadata) |> merge_metadata(response.metadata),
               attachments: edited_attachments(sent, payload, upload_candidates, response.metadata)
           }}
        end
    end
  end

  defp merge_metadata(metadata, updates) do
    updated_keys = MapSet.new(Map.keys(updates), &metadata_key/1)

    metadata
    |> Map.reject(fn {key, _value} -> MapSet.member?(updated_keys, metadata_key(key)) end)
    |> Map.merge(updates)
  end

  defp metadata_key(key) when is_atom(key), do: Atom.to_string(key)
  defp metadata_key(key), do: key

  defp previous_metadata(sent), do: merge_metadata(sent.metadata, sent.response.metadata)

  defp edit_opts(sent, opts, []),
    do: Keyword.put(merge_opts(sent, opts), :previous_metadata, previous_metadata(sent))

  defp edit_opts(sent, opts, uploads),
    do: Keyword.put(edit_opts(sent, opts, []), :files, FileUpload.normalize_many(uploads))

  defp edited_attachments(sent, payload, uploads, metadata) do
    fallback = if uploads == [], do: sent.attachments, else: PostPayload.outbound_attachments(payload)
    metadata |> response_attachments(fallback) |> Attachment.normalize_many()
  end

  defp response_attachments(metadata, fallback) do
    case Map.get(metadata, :attachments, Map.get(metadata, "attachments")) do
      attachments when is_list(attachments) -> attachments
      _ -> fallback
    end
  end
end
