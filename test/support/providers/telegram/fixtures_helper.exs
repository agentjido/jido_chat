defmodule Jido.Chat.Telegram.ContractFixtures do
  @moduledoc false
  import ExUnit.Assertions
  alias Jido.Chat
  alias Jido.Chat.Telegram

  @root Path.expand("../../../contracts/fixtures/telegram", __DIR__)
  @cases @root |> Path.join("provider_cases.json") |> File.read!() |> Jason.decode!()
  @manifest @root |> Path.join("adapter_api.json") |> File.read!() |> Jason.decode!()
  @entries @root |> Path.join("telegram_signals.json") |> File.read!() |> Jason.decode!() |> Map.fetch!("definitions")
  @incoming @root |> Path.join("incoming_updates.json") |> File.read!() |> Jason.decode!()
  @trace "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

  def cases, do: @cases
  def manifest, do: @manifest
  def entries, do: @entries
  def incoming, do: @incoming
  def trace, do: @trace
  def module(name), do: Code.ensure_loaded!(Module.concat([name]))
  def entry(definition), do: Enum.find(@entries, &(&1["module"] == inspect(definition)))
  def provider_case(action), do: Enum.find(@cases, &(&1["action"] == inspect(action)))

  def client(id \\ "alpha", config \\ []) do
    Chat.Client.new!(Telegram.Adapter,
      id: id,
      credentials: %{token: "fixture-token:" <> id, secret_token: "fixture-secret:" <> id},
      config: Keyword.merge([observer: self(), bot_id: 99, bot_username: "contract_bot"], config),
      transport: __MODULE__.Transport
    )
  end

  def scope(value, client) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, if(key == "client_id", do: client.id, else: scope(item, client))} end)

  def scope(value, client) when is_list(value), do: Enum.map(value, &scope(&1, client))
  def scope("fixture-secret:alpha", client), do: "fixture-secret:" <> client.id
  def scope(value, _client), do: value

  def request(action, client, fields \\ %{}) do
    base =
      case provider_case(action) do
        nil -> %{}
        row -> row["fields"] |> scope(client)
      end

    action.signal_definition().new!(
      base |> Map.merge(fields) |> Map.merge(%{"client_id" => client.id, "request_id" => "contract-request"}),
      source: client.source,
      extensions: %{"traceparent" => @trace, "tracestate" => "contract=telegram"}
    )
  end

  def run(action, client, fields \\ %{}, opts \\ []) do
    Jido.Chat.Telegram.ActionHelpers.execute(action, request(action, client, fields), %{client: client, options: opts},
      max_attempts: 1
    )
  end

  def completed(action, client, request, result) do
    assert result.type == Module.concat(action, Completed).type()
    assert result.source == client.source
    assert result.data["client_id"] == client.id
    assert result.data["request_id"] == request.data["request_id"]
    assert result.data["operation"] == request.type
    assert result.extensions["traceparent"] == @trace
    assert result.extensions["tracestate"] == "contract=telegram"
    assert result.extensions["jidocausationid"] == request.id
    assert {:ok, _} = action.validate_output(result.data)
    assert {:error, _} = action.validate_output(request.data)
    assert round_trip(result) == result
    result
  end

  def round_trip(signal, catalog \\ Telegram.catalog()) do
    assert {:ok, json} = Jido.Signal.Codec.serialize(signal)
    refute json =~ "fixture-token:"
    refute json =~ "fixture-secret:"
    refute json =~ "never-project-this"
    assert {:ok, decoded} = Jido.Signal.Catalog.decode(catalog, json)
    decoded
  end

  def projection(signal), do: {signal.type, signal.source, signal.subject, signal.data}

  def public_exports(module) do
    Code.ensure_loaded!(module)
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

  def response(method, payload) when method in ["sendMessage", "sendRichMessage", "editMessageText"] do
    text = payload["text"] || get_in(payload, ["rich_message", "markdown"]) || get_in(payload, ["rich_message", "html"])

    {:ok,
     %{
       "message_id" => 42,
       "chat" => %{"id" => payload["chat_id"]},
       "text" => text,
       "message_thread_id" => payload["message_thread_id"],
       "reply_to_message" => %{"message_id" => get_in(payload, ["reply_parameters", "message_id"])}
     }}
  end

  def response("getChat", payload),
    do: {:ok, %{"id" => payload["chat_id"], "type" => "private", "first_name" => "Contract Peer"}}

  def response("createForumTopic", payload), do: {:ok, %{"message_thread_id" => 7, "name" => payload["name"]}}
  def response("downloadFile", _payload), do: {:ok, <<0, 255, 1, 2>>}

  def response(method, _payload)
      when method in ["deleteMessage", "sendChatAction", "setMessageReaction", "sendRichMessageDraft"],
      do: {:ok, true}

  def response(method, payload) do
    row = Enum.find(@cases, &(&1["method"] == method)) || raise "unexpected contract transport method"
    reply = row["provider_reply"]

    reply =
      if is_map(reply) and is_map(reply["chat"]), do: put_in(reply, ["chat", "id"], payload["chat_id"]), else: reply

    {:ok, reply}
  end
end

defmodule Jido.Chat.Telegram.ContractFixtures.Transport do
  @moduledoc false
  @behaviour Jido.Chat.Telegram.Transport
  alias Jido.Chat.Telegram.ContractFixtures, as: F

  @impl true
  def call(token, method, payload, opts) do
    send(opts[:observer], {:telegram_contract_wire, token, method, payload, opts, self()})

    case opts[:contract_response] do
      nil -> F.response(method, payload)
      :raise -> raise "never-project-this provider exception"
      :throw -> throw("never-project-this provider throw")
      :block -> receive do: (:release -> F.response(method, payload))
      fun when is_function(fun, 2) -> fun.(method, payload)
      result -> result
    end
  end
end

defmodule Jido.Chat.Telegram.ContractFixtures.MixedFlow do
  @moduledoc false
  use Jido.Flow, name: "telegram_contract_mixed_flow"

  flow do
    step("message", action: Jido.Chat.SendMessage, params: input(:message))
    step("poll", action: Jido.Chat.Telegram.SendPoll, params: input(:poll), needs: ["message"])
    output(%{message: result("message"), poll: result("poll")})
  end
end
