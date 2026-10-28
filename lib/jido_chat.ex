defmodule Jido.Chat do
  use Boundary,
    deps: [],
    exports: {:all, except: [Schema, Value, Wire, Plugin.Runtime]}

  @moduledoc """
  Chat SDK and optional Runtime for the Jido ecosystem.

  Core owns canonical chat types, adapter contracts, portable references, and
  synchronous provider calls. `Jido.Chat.Plugin` and `Jido.Chat.Sensor` connect
  provider clients to one Jido Agent activation. `Jido.Chat.Runtime` owns the
  optional room, participant, bridge, provider-work, and storage contracts.

  Starting the `:jido_chat` application starts no Chat process or storage
  resource.
  """

  @doc "Returns the explicit public Signal definition list for this domain."
  @spec signal_definitions() :: [module()]
  def signal_definitions do
    Enum.flat_map(actions(), & &1.signal_definitions()) ++ event_definitions()
  end

  @doc "Returns the core incoming fact definitions."
  @spec event_definitions() :: [module()]
  def event_definitions do
    [
      Jido.Chat.Signal.MessageReceived,
      Jido.Chat.Signal.MessageUpdated,
      Jido.Chat.Signal.MessageDeleted,
      Jido.Chat.Signal.ReactionAdded,
      Jido.Chat.Signal.ReactionRemoved,
      Jido.Chat.Signal.ActionReceived,
      Jido.Chat.Signal.ModalSubmitted,
      Jido.Chat.Signal.ModalClosed,
      Jido.Chat.Signal.OptionsRequested,
      Jido.Chat.Signal.SlashCommandReceived,
      Jido.Chat.Signal.AssistantThreadStarted,
      Jido.Chat.Signal.AssistantContextChanged,
      Jido.Chat.Signal.MembershipChanged,
      Jido.Chat.Signal.ThreadStarted,
      Jido.Chat.Signal.ReceiptReceived,
      Jido.Chat.Signal.NormalizationFailed,
      Jido.Chat.Signal.ThreadChanged
    ]
  end

  @doc "Returns the configured adapter's admitted incoming fact definitions."
  @spec event_definitions(Jido.Chat.Client.t()) :: [module()]
  def event_definitions(%Jido.Chat.Client{adapter: adapter}), do: Jido.Chat.Adapter.event_definitions(adapter)

  @doc "Returns core and configured provider Signal definitions."
  @spec signal_definitions(Jido.Chat.Client.t()) :: [module()]
  def signal_definitions(%Jido.Chat.Client{} = client) do
    (signal_definitions() ++ Enum.flat_map(actions(client), & &1.signal_definitions()) ++ event_definitions(client))
    |> Enum.uniq()
  end

  @doc "Returns the configured core and provider Signal catalog without I/O."
  @spec catalog(Jido.Chat.Client.t()) :: Jido.Signal.Catalog.t()
  def catalog(%Jido.Chat.Client{} = client), do: Jido.Signal.Catalog.new!(signal_definitions(client))

  @doc "Returns the native Signal catalog. This function starts no process."
  @spec catalog() :: Jido.Signal.Catalog.t()
  def catalog, do: Jido.Signal.Catalog.new!(signal_definitions())

  @doc "Returns Signal definition and Action pairs for all operations."
  @spec operations() :: [{module(), module()}]
  def operations do
    Jido.Chat.Operations.Definitions.all()
    |> Enum.map(fn {_, {definition, _, _, _, _}} ->
      {definition, Module.concat(__MODULE__, definition |> Module.split() |> List.last())}
    end)
    |> Enum.sort()
  end

  @doc "Returns core and configured provider request/Action pairs."
  @spec operations(Jido.Chat.Client.t()) :: [{module(), module()}]
  def operations(%Jido.Chat.Client{adapter: adapter}) do
    (operations() ++ Jido.Chat.Adapter.operations(adapter)) |> Enum.sort()
  end

  @doc "Returns core and configured provider Action modules."
  @spec actions(Jido.Chat.Client.t()) :: [module()]
  def actions(%Jido.Chat.Client{} = client), do: Enum.map(operations(client), &elem(&1, 1))

  @doc "Returns all adapter agnostic Action modules."
  @spec actions() :: [module()]
  def actions, do: Enum.map(operations(), &elem(&1, 1))

  @doc """
  Returns the configured adapter's operation support without I/O.

  Each core operation has status `:native` or `:unsupported`. Keys are canonical
  operation names; `:send_message` covers `send_text/4`. This reads a declaration,
  not the bot's permissions or current provider availability.
  """
  @spec capabilities(Jido.Chat.Client.t()) :: Jido.Chat.Adapter.capabilities()
  def capabilities(%Jido.Chat.Client{adapter: adapter}), do: Jido.Chat.Adapter.capabilities(adapter)

  @doc """
  Executes one core or configured provider request with its native Jido Action.

  Options are `:options` for private adapter options and `:timeout` for the
  execution deadline in milliseconds or `:infinity` (the default). Only one
  attempt is made. A deadline failure has an unknown provider outcome.
  """
  @spec execute(Jido.Chat.Client.t(), Jido.Signal.t(), keyword()) :: {:ok, Jido.Signal.t()} | {:error, term()}
  def execute(client, request, opts \\ [])

  def execute(%Jido.Chat.Client{} = client, %Jido.Signal{} = request, opts) when is_list(opts) do
    with {:ok, private, timeout} <- execution_options(opts),
         {:ok, request} <- Jido.Chat.Signal.Policy.prepare(request),
         {_definition, action} <-
           Enum.find(operations(client), fn {definition, _} -> definition.type() == request.type end) do
      case Jido.Exec.run(action, request.data, %{client: client, signal: request, options: private},
             max_attempts: 1,
             timeout: timeout
           ) do
        {:ok, data} ->
          with {:ok, signal} <-
                 action.reply(request, data,
                   source: client.source,
                   subject:
                     request.subject ||
                       if(request.data["room_id"],
                         do: Jido.Chat.Signal.Identity.conversation_subject(client.id, request.data["room_id"])
                       )
                 ),
               do: Jido.Chat.Signal.Policy.prepare(signal)

        {:error, %Jido.Action.Error.TimeoutError{}} ->
          Jido.ChatAction.Execution.timeout(action, client, request)

        {:error, _} = error ->
          error
      end
    else
      {:error, _} = error -> error
      _ -> Jido.Chat.Signal.Policy.error(:invalid_request)
    end
  end

  def execute(_, _, _), do: Jido.Chat.Signal.Policy.error(:invalid_request)

  defp execution_options(opts) do
    with true <- Keyword.keyword?(opts),
         true <- Keyword.keys(opts) -- [:options, :timeout] == [],
         true <- length(opts) == length(Enum.uniq_by(opts, &elem(&1, 0))),
         private = Keyword.get(opts, :options, []),
         true <- is_list(private) and Keyword.keyword?(private),
         timeout = Keyword.get(opts, :timeout, :infinity),
         true <- timeout == :infinity or (is_integer(timeout) and timeout >= 0) do
      {:ok, private, timeout}
    else
      _ -> Jido.Chat.Signal.Policy.error(:invalid_options)
    end
  end

  @doc """
  Builds and executes a SendMessage Signal for an immutable client.

  Data keys are strings and include `request_id`. Execution options match
  `execute/3`: private `:options` and an execution `:timeout`.
  """
  @spec send_message(Jido.Chat.Client.t(), map(), keyword()) :: {:ok, Jido.Signal.t()} | {:error, term()}
  def send_message(client, data, opts \\ [])

  def send_message(%Jido.Chat.Client{} = client, data, opts)
      when is_map(data) and not is_struct(data) and is_list(opts) do
    with {:ok, request} <-
           Jido.Chat.Signal.Policy.new(Jido.Chat.Signal.SendMessage, Map.put_new(data, "client_id", client.id)) do
      execute(client, request, opts)
    end
  end

  def send_message(_, _, _), do: Jido.Chat.Signal.Policy.error(:invalid_request)

  @doc """
  Sends text through `Jido.Chat.SendMessage` and returns its completion Signal.

  Options: `:request_id`, `:format`, `:thread_id`, `:reply_to_id`, and `:keyboard`.
  Formats accept `:plain`, `:markdown`, or `:html` (or their string values).
  A request ID is generated when omitted. `:options` holds private adapter options;
  `:signal_options` holds Signal constructor options, including trace extensions. `:timeout` sets the deadline in milliseconds, or `:infinity`
  (the default).
  """
  @spec send_text(Jido.Chat.Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, Jido.Signal.t()} | {:error, term()}
  def send_text(client, room_id, text, opts \\ []) do
    execute_request(client, Jido.Chat.Signal.SendMessage, %{"room_id" => room_id, "text" => text}, opts, [
      :format,
      :thread_id,
      :reply_to_id,
      :keyboard
    ])
  end

  @doc """
  Delivers text chunks through one synchronous `Jido.Chat.StreamText` execution.

  The adapter selects native streaming, draft previews, edits, or buffering.
  Options match `send_text/4`, with `:update_interval_ms` for the minimum interval
  between intermediate writes. The final content is flushed when the source ends.
  The lazy Enumerable stays in private Action context at `options[:stream]`;
  the command and result are serializable Signals. Jido.Exec uses its temporary
  execution task. Jido Chat owns no stream worker or stored state.
  """
  @spec stream_text(Jido.Chat.Client.t(), String.t(), Enumerable.t(), keyword()) ::
          {:ok, Jido.Signal.t()} | {:error, term()}
  def stream_text(client, room_id, chunks, opts \\ []) do
    if Enumerable.impl_for(chunks) do
      execute_request(
        client,
        Jido.Chat.Signal.StreamText,
        %{"room_id" => room_id},
        opts,
        [:format, :thread_id, :reply_to_id, :keyboard, :update_interval_ms],
        stream: chunks
      )
    else
      Jido.Chat.Signal.Policy.error(:invalid_stream)
    end
  end

  @doc """
  Sends a file through `Jido.Chat.SendFile` and returns its completion Signal.

  Source is a file source map accepted by `Jido.Chat.Signal.SendFile`: a portable
  file, URL, or provider reference, or base64 content with a filename.
  Options match `send_text/4`, with `:caption` and `:media_kind` (`:file` or `:image`).
  """
  @spec send_file(Jido.Chat.Client.t(), String.t(), map(), keyword()) ::
          {:ok, Jido.Signal.t()} | {:error, term()}
  def send_file(client, room_id, source, opts \\ []) do
    execute_request(client, Jido.Chat.Signal.SendFile, %{"room_id" => room_id, "source" => source}, opts, [
      :format,
      :thread_id,
      :reply_to_id,
      :keyboard,
      :caption,
      :media_kind
    ])
  end

  @doc """
  Edits text through `Jido.Chat.EditMessage` and returns its completion Signal.

  Options: `:request_id`, `:format`, `:keyboard`, `:options`, `:signal_options`, and `:timeout`.
  Formatting accepts the same values as `send_text/4`. Use `%{"rows" => []}` to
  clear a keyboard. An edit does not change the message's room, thread, or parent.
  """
  @spec edit_message(Jido.Chat.Client.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Jido.Signal.t()} | {:error, term()}
  def edit_message(client, room_id, message_id, text, opts \\ []) do
    execute_request(
      client,
      Jido.Chat.Signal.EditMessage,
      %{"room_id" => room_id, "message_id" => message_id, "text" => text},
      opts,
      [:format, :keyboard]
    )
  end

  @doc """
  Deletes a message through `Jido.Chat.DeleteMessage` and returns its completion Signal.

  Result data contains `result["acknowledged"]`. Options: `:request_id`, `:options`,
  `:signal_options`, and `:timeout`. Provider permissions and deletion limits still apply.
  """
  @spec delete_message(Jido.Chat.Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, Jido.Signal.t()} | {:error, term()}
  def delete_message(client, room_id, message_id, opts \\ []) do
    execute_request(
      client,
      Jido.Chat.Signal.DeleteMessage,
      %{"room_id" => room_id, "message_id" => message_id},
      opts,
      []
    )
  end

  @doc """
  Downloads a client-scoped reference through `Jido.Chat.DownloadFile`.

  Returns a completion Signal with base64 bytes in `data["result"]["content_base64"]`.
  Options: `:request_id`, `:options`, `:signal_options`, and `:timeout`. The existing Signal
  envelope size limit applies. The host decides how to save or use the bytes.
  """
  @spec download_file(Jido.Chat.Client.t(), map(), keyword()) :: {:ok, Jido.Signal.t()} | {:error, term()}
  def download_file(client, resource_ref, opts \\ []) do
    execute_request(client, Jido.Chat.Signal.DownloadFile, %{"resource_ref" => resource_ref}, opts, [])
  end

  @doc """
  Adds a reaction through `Jido.Chat.AddReaction` and returns its completion Signal.

  Reaction is a string supported by the provider. Options: `:request_id`,
  `:options`, `:signal_options`, and `:timeout`. Result data contains `result["acknowledged"]`.
  """
  @spec add_reaction(Jido.Chat.Client.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Jido.Signal.t()} | {:error, term()}
  def add_reaction(client, room_id, message_id, reaction, opts \\ []) do
    execute_request(
      client,
      Jido.Chat.Signal.AddReaction,
      %{"room_id" => room_id, "message_id" => message_id, "reaction" => reaction},
      opts,
      []
    )
  end

  @doc """
  Removes a reaction through `Jido.Chat.RemoveReaction` and returns its completion Signal.

  Options and result match `add_reaction/5`. The adapter maps removal to the
  provider's reaction model.
  """
  @spec remove_reaction(Jido.Chat.Client.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Jido.Signal.t()} | {:error, term()}
  def remove_reaction(client, room_id, message_id, reaction, opts \\ []) do
    execute_request(
      client,
      Jido.Chat.Signal.RemoveReaction,
      %{"room_id" => room_id, "message_id" => message_id, "reaction" => reaction},
      opts,
      []
    )
  end

  @doc """
  Fetches room metadata through `Jido.Chat.FetchMetadata`.

  Returns a completion Signal with `id`, `kind`, and optional `name` in
  `data["result"]`. Options: `:request_id`, `:options`, `:signal_options`, and `:timeout`.
  This queries the provider once. Jido Chat does not store the result.
  """
  @spec fetch_metadata(Jido.Chat.Client.t(), String.t(), keyword()) :: {:ok, Jido.Signal.t()} | {:error, term()}
  def fetch_metadata(client, room_id, opts \\ []) do
    execute_request(client, Jido.Chat.Signal.FetchMetadata, %{"room_id" => room_id}, opts, [])
  end

  @doc """
  Sends one typing notice through `Jido.Chat.StartTyping`.

  Options: `:thread_id`, `:request_id`, `:options`, `:signal_options`, and `:timeout`.
  Returns a completion Signal with `result["acknowledged"]`. The host decides
  when to repeat the call. Jido Chat starts no timer or background worker.
  """
  @spec start_typing(Jido.Chat.Client.t(), String.t(), keyword()) :: {:ok, Jido.Signal.t()} | {:error, term()}
  def start_typing(client, room_id, opts \\ []) do
    execute_request(client, Jido.Chat.Signal.StartTyping, %{"room_id" => room_id}, opts, [:thread_id])
  end

  @doc """
  Creates a named thread through `Jido.Chat.CreateThread`.

  Returns a completion Signal with `id`, `room_id`, and `name` in `data["result"]`.
  Use the returned `id` as `thread_id` in `send_text/4` or `start_typing/3`.
  Options: `:request_id`, `:options`, `:signal_options`, and `:timeout`. The provider must
  support thread creation in the room and allow the client to create threads.
  """
  @spec create_thread(Jido.Chat.Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, Jido.Signal.t()} | {:error, term()}
  def create_thread(client, room_id, name, opts \\ []) do
    execute_request(client, Jido.Chat.Signal.CreateThread, %{"room_id" => room_id, "name" => name}, opts, [])
  end

  defp execute_request(client, definition, data, opts, fields, private \\ [])

  defp execute_request(%Jido.Chat.Client{} = client, definition, data, opts, fields, private) when is_list(opts) do
    allowed = [:request_id, :options, :signal_options, :timeout | fields]

    with true <- Keyword.keyword?(opts),
         true <- Keyword.keys(opts) -- allowed == [],
         true <- length(opts) == length(Enum.uniq_by(opts, &elem(&1, 0))),
         options = Keyword.get(opts, :options, []),
         true <- is_list(options) and Keyword.keyword?(options),
         false <- Keyword.has_key?(options, :stream),
         signal_opts = Keyword.get(opts, :signal_options, []),
         :ok <- Jido.Chat.Signal.Policy.constructor_options(signal_opts),
         request_data =
           opts
           |> Keyword.take(fields)
           |> Map.new(fn {key, value} -> {Atom.to_string(key), request_value(key, value)} end)
           |> Map.merge(data)
           |> Map.put("client_id", client.id)
           |> Map.put("request_id", Keyword.get_lazy(opts, :request_id, &Jido.Signal.ID.generate!/0)),
         {:ok, request} <-
           Jido.Chat.Signal.Policy.new(
             definition,
             request_data,
             Map.put_new(Map.new(signal_opts, fn {key, value} -> {to_string(key), value} end), "source", client.source)
           ) do
      execute(client, request,
        options: Keyword.merge(options, private),
        timeout: Keyword.get(opts, :timeout, :infinity)
      )
    else
      {:error, _} = error -> error
      _ -> Jido.Chat.Signal.Policy.error(:invalid_options)
    end
  end

  defp execute_request(_, _, _, _, _, _), do: Jido.Chat.Signal.Policy.error(:invalid_client)

  defp request_value(:format, value) when value in [:plain, :markdown, :html], do: Atom.to_string(value)
  defp request_value(:media_kind, value) when value in [:file, :image], do: Atom.to_string(value)
  defp request_value(_, value), do: value

  @doc "Normalizes provider input to an ordered, fully validated delivery of Signals."
  @spec normalize(Jido.Chat.Client.t(), term(), keyword()) :: {:ok, Jido.Chat.Delivery.t()} | {:error, term()}
  def normalize(client, input, opts \\ [])

  def normalize(%Jido.Chat.Client{} = client, input, opts) when is_list(opts) do
    case client.adapter.normalize(client, input, opts) do
      {:ok, %Jido.Chat.Delivery{} = delivery} -> Jido.Chat.Delivery.validate(client, delivery)
      {:error, %Jido.Chat.Errors.Contract{}} = error -> error
      _ -> Jido.Chat.Signal.Policy.error(:invalid_delivery)
    end
  rescue
    _ -> Jido.Chat.Signal.Policy.error(:invalid_delivery)
  catch
    _, _ -> Jido.Chat.Signal.Policy.error(:invalid_delivery)
  end

  def normalize(_, _, _), do: Jido.Chat.Signal.Policy.error(:invalid_client)

  @doc "Renders a portable emoji value."
  @spec emoji(String.t(), keyword()) :: String.t()
  def emoji(value, opts \\ []), do: Jido.Chat.Emoji.render(value, opts)
end
