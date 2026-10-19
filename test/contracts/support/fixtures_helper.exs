defmodule Jido.Chat.ContractFixtures do
  @moduledoc false
  import ExUnit.Assertions
  alias Jido.Chat

  @signals __DIR__
           |> Path.join("../fixtures/core_signals.json")
           |> File.read!()
           |> Jason.decode!()
           |> Map.fetch!("definitions")
  @trace "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

  def entries, do: @signals
  def trace, do: @trace
  def module(name), do: Module.concat([name])
  def entry(module), do: Enum.find(@signals, &(&1["module"] == inspect(module)))

  def pairs do
    for entry <- @signals, entry["kind"] in ["command", "query"] do
      {module(entry["module"]), module(String.replace(entry["module"], "Jido.Chat.Signal.", "Jido.Chat."))}
    end
    |> Enum.sort()
  end

  def capabilities do
    Map.new(pairs(), fn {definition, _action} ->
      {definition |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom(), :native}
    end)
  end

  def client(adapter \\ __MODULE__.FirstAdapter, id \\ "alpha") do
    Chat.Client.new!(adapter,
      id: id,
      credentials: %{token: "private-token:" <> id},
      config: [observer: self(), private_setting: "private-config:" <> id],
      transport: __MODULE__
    )
  end

  def scope(value, client) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, if(key == "client_id", do: client.id, else: scope(item, client))} end)

  def scope(value, client) when is_list(value), do: Enum.map(value, &scope(&1, client))
  def scope(value, _client), do: value

  def request(action, client, overrides \\ %{}) do
    {definition, ^action} = Enum.find(pairs(), fn {_, module} -> module == action end)
    data = entry(definition)["fixture"] |> scope(client) |> Map.merge(overrides)

    definition.new!(data,
      source: client.source,
      extensions: %{"traceparent" => @trace, "tracestate" => "contract=fixture"}
    )
  end

  def result(request, client, adapter) do
    {_, action} = Enum.find(pairs(), fn {definition, _} -> definition.type() == request.type end)
    result = entry(Module.concat(action, Completed))["fixture"]["result"] |> scope(client)
    result = if Map.has_key?(result, "room_id"), do: Map.put(result, "room_id", request.data["room_id"]), else: result
    result = if Map.has_key?(result, "id"), do: Map.put(result, "id", inspect(adapter) <> ":provider-id"), else: result
    result = if action == Chat.CreateThread, do: Map.put(result, "name", request.data["name"]), else: result

    if action in [Chat.SendMessage, Chat.EditMessage, Chat.SendFile, Chat.StreamText] do
      Map.put(result, "text", request.data["text"] || request.data["caption"] || "")
    else
      result
    end
  end

  def invoke(adapter, client, request, opts) do
    send(client.config[:observer], {:contract_invoke, adapter, client.id, request, opts, self()})

    case Keyword.get(opts, :provider_return, :canonical) do
      :raise ->
        raise "private provider details"

      :throw ->
        throw("private provider details")

      :block ->
        receive do: (:release -> {:ok, result(request, client, adapter)})

      :canonical ->
        result = result(request, client, adapter)

        result =
          if request.type == Chat.Signal.StreamText.type(),
            do: Map.put(result, "text", Enum.join(opts[:stream])),
            else: result

        {:ok, result}

      other ->
        other
    end
  end

  def normalize(client, input, opts) do
    send(client.config[:observer], {:contract_normalize, client.id, input, opts})

    case Keyword.get(opts, :normalize_return, {:ok, input}) do
      :raise -> raise "private normalization details"
      :throw -> throw("private normalization details")
      other -> other
    end
  end

  def message(client, overrides \\ %{}) do
    data =
      %{
        "item_id" => "item-1",
        "delivery_id" => "delivery-1",
        "room_id" => "room/1",
        "message_id" => "message-1",
        "sender" => %{"id" => "user-1"},
        "text" => "Hello"
      }
      |> Map.merge(overrides)

    Chat.Signal.MessageReceived.new!(data,
      source: client.source,
      subject: Chat.Signal.Identity.conversation_subject(client.id, data["room_id"])
    )
  end

  def round_trip(signal, catalog \\ Chat.catalog()) do
    assert {:ok, ^signal} = Jido.Signal.Catalog.validate(catalog, signal)
    assert {:ok, encoded} = Jido.Signal.Serialization.serialize(signal)
    assert {:ok, ^signal} = Jido.Signal.Catalog.decode(catalog, encoded)
    refute encoded =~ "private-token"
    refute encoded =~ "private-config"
    refute encoded =~ "private provider"
    signal
  end

  def public_exports(module) do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)
    hidden = for {{kind, name, arity}, _, _, false, _} <- docs, do: {kind, name, arity}

    for kind <- [:functions, :macros],
        {name, arity} <- module.__info__(kind),
        name not in [:__struct__, :__info__],
        {if(kind == :macros, do: :macro, else: :function), name, arity} not in hidden do
      [Atom.to_string(name), arity, if(kind == :macros, do: "macro", else: "function")]
    end
    |> Enum.sort()
  end
end

defmodule Jido.Chat.ContractFixtures.FirstAdapter do
  use Jido.Chat.Adapter
  alias Jido.Chat.ContractFixtures, as: Fixtures
  @impl true
  def channel_type, do: :first
  @impl true
  def capabilities, do: Fixtures.capabilities()
  @impl true
  def default_transport, do: Fixtures
  @impl true
  def invoke(client, request, opts), do: Fixtures.invoke(__MODULE__, client, request, opts)
  @impl true
  def normalize(client, input, opts), do: Fixtures.normalize(client, input, opts)
end

defmodule Jido.Chat.ContractFixtures.SecondAdapter do
  use Jido.Chat.Adapter
  alias Jido.Chat.ContractFixtures, as: Fixtures
  @impl true
  def channel_type, do: :second
  @impl true
  def capabilities, do: Fixtures.capabilities()
  @impl true
  def invoke(client, request, opts), do: Fixtures.invoke(__MODULE__, client, request, opts)
  @impl true
  def normalize(client, input, opts), do: Fixtures.normalize(client, input, opts)
end

defmodule Jido.Chat.ContractFixtures.UnsupportedAdapter do
  use Jido.Chat.Adapter
  @impl true
  def capabilities, do: %{}
  @impl true
  def invoke(client, _, _) do
    send(client.config[:observer], :unsupported_provider_called)
    raise "An unsupported provider must not be called"
  end

  @impl true
  def normalize(client, input, opts), do: Jido.Chat.ContractFixtures.normalize(client, input, opts)
end

defmodule Jido.Chat.ContractFixtures.ProviderRequest do
  use Jido.Chat.Signal.Definition,
    owner: :contract_provider,
    kind: :query,
    type: "contract.chat.query.status",
    dataschema: "urn:contract:chat:status:1",
    default_source: "urn:contract:provider",
    schema:
      Zoi.map(%{"client_id" => Zoi.string() |> Zoi.min(1), "request_id" => Zoi.string() |> Zoi.min(1)},
        unrecognized_keys: :error
      )
end

defmodule Jido.Chat.ContractFixtures.ProviderAction do
  use Jido.ChatAction,
    name: "contract_provider_status",
    signal: Jido.Chat.ContractFixtures.ProviderRequest,
    result_schema: Zoi.map(%{"status" => Zoi.enum(["ready"])}, unrecognized_keys: :error)

  @impl true
  def invoke(client, request, opts) do
    send(client.config[:observer], {:provider_extension, request, opts})
    {:ok, %{"status" => "ready"}}
  end
end

defmodule Jido.Chat.ContractFixtures.ProviderFact do
  use Jido.Chat.Signal.Definition,
    owner: :contract_provider,
    kind: :fact,
    type: "contract.chat.presence.changed",
    dataschema: "urn:contract:chat:presence:1",
    default_source: "urn:contract:provider",
    schema:
      Zoi.map(
        %{
          "item_id" => Zoi.string() |> Zoi.min(1),
          "delivery_id" => Zoi.string() |> Zoi.min(1),
          "room_id" => Zoi.string() |> Zoi.min(1),
          "online" => Zoi.boolean()
        },
        unrecognized_keys: :error
      )
end

defmodule Jido.Chat.ContractFixtures.ExtendedAdapter do
  use Jido.Chat.Adapter
  alias Jido.Chat.ContractFixtures, as: Fixtures
  @impl true
  def capabilities, do: %{send_message: :native}
  @impl true
  def operations, do: [{Fixtures.ProviderRequest, Fixtures.ProviderAction}]
  @impl true
  def event_definitions, do: [Fixtures.ProviderFact, Jido.Chat.Signal.MessageReceived]
  @impl true
  def invoke(client, request, opts), do: Fixtures.invoke(__MODULE__, client, request, opts)
  @impl true
  def normalize(client, input, opts), do: Fixtures.normalize(client, input, opts)
end

defmodule Jido.Chat.ContractFixtures.ReplyFlow do
  use Jido.Flow, name: "contract_reply_flow"

  flow do
    step("first", action: Jido.Chat.SendMessage, params: %{signal: input(:first)})
    step("second", action: Jido.Chat.SendMessage, params: %{signal: input(:second)}, needs: ["first"])
    output(%{first: result("first", [:signal]), second: result("second", [:signal])})
  end
end
