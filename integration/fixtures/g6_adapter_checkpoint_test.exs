defmodule Jido.Chat.Integration.G6AdapterCheckpointTest do
  use ExUnit.Case, async: false
  alias Jido.Chat.{Delivery, WebhookRequest}
  @directory Path.expand("../../docs/migration", __DIR__)
  @matrix @directory |> Path.join("adapter-matrix.json") |> File.read!() |> Jason.decode!()

  test "all nine bindings start at protocol 1 with their frozen operation support" do
    for row <- @matrix["adapters"] do
      adapter = Module.concat([row["adapter_module"]])
      assert adapter.signal_protocol() == 1
      opts = [id: row["package"], token: "fixture-token"]
      assert {:ok, binding} = Jido.Chat.bind(adapter, opts)
      assert binding.adapter == adapter
      capabilities = Jido.Chat.Adapter.capabilities(adapter)

      for {operation, support} <- row["operation_support"] do
        assert Atom.to_string(capabilities[String.to_existing_atom(operation)]) == support
      end
    end
  end

  defp github do
    payload = %{
      "action" => "created",
      "repository" => %{"name" => "repo", "owner" => %{"login" => "owner"}},
      "issue" => %{"id" => 9, "number" => 42},
      "comment" => %{"id" => 1, "body" => "body", "user" => %{"id" => 1}}
    }

    raw = Jason.encode!(payload)

    headers = %{
      "x-github-event" => "issue_comment",
      "x-github-delivery" => "g6",
      "x-hub-signature-256" =>
        "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, "fixture", raw), case: :lower)
    }

    {Jido.Chat.GitHub.Adapter, [webhook_secret: "fixture"],
     WebhookRequest.new(%{payload: payload, raw: raw, headers: headers})}
  end

  defp discord do
    {public, private} = :crypto.generate_key(:eddsa, :ed25519)

    payload = %{
      "id" => "m1",
      "channel_id" => "C1",
      "content" => "body",
      "author" => %{"id" => "u1"}
    }

    raw = Jason.encode!(payload)
    timestamp = "1706745600"

    signature =
      :crypto.sign(:eddsa, :none, timestamp <> raw, [private, :ed25519])
      |> Base.encode16(case: :lower)

    {Jido.Chat.Discord.Adapter, [public_key: Base.encode16(public, case: :lower)],
     WebhookRequest.new(%{
       payload: payload,
       raw: raw,
       headers: %{"x-signature-ed25519" => signature, "x-signature-timestamp" => timestamp}
     })}
  end

  defp x do
    payload = %{
      "direct_message_events" =>
        Enum.map(1..3, fn id ->
          %{
            "id" => "#{id}",
            "type" => "message_create",
            "message_create" => %{"sender_id" => "u1", "message_data" => %{"text" => "#{id}"}}
          }
        end)
    }

    raw = Jason.encode!(payload)

    {Jido.Chat.X.Adapter, [consumer_secret: "fixture"],
     WebhookRequest.new(%{
       payload: payload,
       raw: raw,
       headers: %{
         "x-twitter-webhooks-signature" =>
           "sha256=" <> Base.encode64(:crypto.mac(:hmac, :sha256, "fixture", raw))
       }
     })}
  end

  defp teams do
    # The package fixtures separately prove the real JWT signature and service URL claim.
    payload = %{
      "type" => "message",
      "id" => "m1",
      "text" => "body",
      "serviceUrl" => "https://fixture.test",
      "conversation" => %{"id" => "C1", "conversationType" => "personal"},
      "from" => %{"id" => "u1"}
    }

    {Jido.Chat.Teams.Adapter, [verifier: fn _, _ -> :ok end],
     WebhookRequest.new(%{payload: payload})}
  end

  defp fixtures do
    [
      discord(),
      github(),
      teams(),
      x(),
      {Jido.Chat.Signal.Adapter, [],
       %{
         "envelope" => %{
           "source" => "u1",
           "timestamp" => 1,
           "dataMessage" => %{"message" => "body", "timestamp" => 1}
         }
       }},
      {Jido.Chat.Mattermost.Adapter, [],
       %{"post" => %{"id" => "m1", "channel_id" => "C1", "user_id" => "u1", "message" => "body"}}},
      {Jido.Chat.WhatsApp.Adapter, [],
       {:amarula, :messages_upsert,
        %{
          id: "g6",
          messages: [
            %{
              id: "m1",
              type: :text,
              channel_jid: "C1@g.us",
              from_jid: "u1@s.whatsapp.net",
              content: "body"
            }
          ]
        }}}
    ]
  end

  test "every G6 provider accepts one complete typed unit with exact source and subject" do
    for {adapter, opts, input} <- fixtures() do
      {:ok, binding} = Jido.Chat.bind(adapter, Keyword.put(opts, :id, inspect(adapter)))
      assert {:ok, unit} = Jido.Chat.normalize_event(binding, input)
      assert {:ok, ^unit} = Delivery.validate(binding, unit)
      assert unit.signals != []

      for fact <- unit.signals do
        assert fact.source == binding.source

        assert fact.subject ==
                 Jido.Chat.Signal.Identity.conversation_subject(binding.id, fact.data["room_id"])

        {:ok, encoded} = Jido.Signal.Serialization.serialize(fact)

        assert {:ok, ^fact} =
                 Jido.Signal.Catalog.decode(
                   Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions()),
                   encoded
                 )
      end

      {:ok, counter} = Agent.start_link(fn -> %{calls: 0, effects: 0} end)
      assert {:ok, :accepted} = accept(binding, input, counter, :ok)
      assert Agent.get(counter, & &1) == %{calls: 1, effects: length(unit.signals)}
    end
  end

  for mode <- [:error, :raise, :throw, :exit, :invalid] do
    test "every G6 provider reports sink #{mode} with one call and zero accepted effects" do
      for {adapter, opts, input} <- fixtures() do
        {:ok, binding} = Jido.Chat.bind(adapter, Keyword.put(opts, :id, inspect(adapter)))
        {:ok, counter} = Agent.start_link(fn -> %{calls: 0, effects: 0} end)
        assert {:error, _} = error = accept(binding, input, counter, unquote(mode))
        assert Agent.get(counter, & &1) == %{calls: 1, effects: 0}

        if adapter in [
             Jido.Chat.Discord.Adapter,
             Jido.Chat.GitHub.Adapter,
             Jido.Chat.Teams.Adapter,
             Jido.Chat.X.Adapter
           ] do
          assert adapter.format_webhook_response(error, []).status >= 400
        end
      end
    end
  end

  defp accept(binding, input, counter, mode) do
    with {:ok, unit} <- Jido.Chat.normalize_event(binding, input),
         {:ok, ^unit} <- Delivery.validate(binding, unit) do
      case sink(counter, unit, mode) do
        {:ok, _} = accepted -> accepted
        {:error, _} = rejected -> rejected
        _ -> {:error, :invalid_sink_result}
      end
    end
  rescue
    _ -> {:error, :sink_exception}
  catch
    _, _ -> {:error, :sink_exception}
  end

  defp sink(counter, unit, mode) do
    Agent.update(counter, &%{&1 | calls: &1.calls + 1})

    case mode do
      :ok ->
        Agent.update(counter, &%{&1 | effects: &1.effects + length(unit.signals)})
        {:ok, :accepted}

      :error ->
        {:error, :sink_rejected}

      :raise ->
        raise "fixture sink"

      :throw ->
        throw(:fixture_sink)

      :exit ->
        exit(:fixture_sink)

      :invalid ->
        :invalid_return
    end
  end
end
