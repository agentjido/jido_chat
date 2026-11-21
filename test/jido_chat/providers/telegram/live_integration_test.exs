defmodule Jido.Chat.Telegram.LiveIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.{Client, Signal}
  alias Jido.Chat.Telegram, as: Telegram
  alias Jido.Chat.Telegram.Adapter

  @run_live System.get_env("RUN_LIVE_TELEGRAM_TESTS") in ["1", "true", "TRUE", "yes", "on"]
  @run_live_ui System.get_env("RUN_LIVE_TELEGRAM_UI_TESTS") in ["1", "true", "TRUE", "yes", "on"]
  @token System.get_env("TELEGRAM_BOT_TOKEN")
  @chat_id System.get_env("TELEGRAM_TEST_CHAT_ID")
  @forum_chat_id System.get_env("TELEGRAM_TEST_FORUM_CHAT_ID")
  @thread_id System.get_env("TELEGRAM_TEST_THREAD_ID")
  @reaction System.get_env("TELEGRAM_TEST_REACTION") || "👍"
  @callback_timeout_ms System.get_env("TELEGRAM_CALLBACK_TIMEOUT_MS", "180000") |> String.to_integer()
  @moduletag :live
  @moduletag :telegram_live
  @moduletag timeout: max(210_000, @callback_timeout_ms + 30_000)
  @moduletag capture_log: true

  if not @run_live do
    @moduletag skip: "set RUN_LIVE_TELEGRAM_TESTS=true to run live Telegram integration tests"
  end

  if @run_live and (@token in [nil, ""] or @chat_id in [nil, ""]) do
    @moduletag skip: "set TELEGRAM_BOT_TOKEN and TELEGRAM_TEST_CHAT_ID"
  end

  defmodule CaptureTransport do
    @behaviour Jido.Chat.Telegram.Transport
    @impl true
    def call(token, method, payload, opts) do
      result = Jido.Chat.Telegram.Transport.ExGramClient.call(token, method, payload, opts)

      if owner = Process.whereis(Jido.Chat.Telegram.LiveIntegrationTest),
        do: send(owner, {:telegram_response, method, payload, result})

      result
    end
  end

  defmodule DraftFlow do
    use Jido.Flow, name: "telegram_live_draft_flow"

    flow do
      step("first", action: Telegram.SendDraft, params: input(:first))
      step("second", action: Telegram.SendDraft, params: input(:second), needs: ["first"])
      step("finish", action: Jido.Chat.SendMessage, params: input(:finish), needs: ["second"])

      output(%{
        first: result("first"),
        second: result("second"),
        signal: result("finish")
      })
    end
  end

  setup do
    Process.register(self(), __MODULE__)
    client = Client.new!(Adapter, id: "telegram.live", credentials: %{token: @token}, transport: CaptureTransport)
    %{client: client, room_id: to_string(@chat_id), nonce: Integer.to_string(System.system_time(:microsecond))}
  end

  test "core send, edit, and delete return native result Signals", ctx do
    sent = run(ctx, Jido.Chat.SendMessage, %{"room_id" => ctx.room_id, "text" => "Jido live send #{ctx.nonce}"})

    edited =
      run(ctx, Jido.Chat.EditMessage, %{
        "room_id" => ctx.room_id,
        "message_id" => sent["id"],
        "text" => "Jido live edit #{ctx.nonce}"
      })

    assert edited["id"] == sent["id"]
    assert edited["status"] == "updated"

    assert run(ctx, Jido.Chat.DeleteMessage, %{"room_id" => ctx.room_id, "message_id" => sent["id"]}) == %{
             "acknowledged" => true
           }
  end

  test "typing, metadata, direct addressing, and bot identity use Actions", ctx do
    assert run(ctx, Jido.Chat.StartTyping, %{"room_id" => ctx.room_id}) == %{"acknowledged" => true}
    assert run(ctx, Jido.Chat.FetchMetadata, %{"room_id" => ctx.room_id})["id"] == ctx.room_id
    assert run(ctx, Jido.Chat.OpenDm, %{"user_id" => ctx.room_id})["id"] == ctx.room_id
    bot = run(ctx, Telegram.GetMe, %{})
    assert bot["is_bot"]
    assert is_binary(bot["username"])
  end

  test "webhook status is read through a native Action without changing delivery", ctx do
    info = run(ctx, Telegram.GetWebhookInfo, %{})
    assert info["url"] == ""
    assert is_integer(info["pending_update_count"])
    assert info["has_custom_certificate"] == false
  end

  test "public send_text and send_file use typed Actions and download the same bytes", ctx do
    assert {:ok, sent} = Jido.Chat.send_text(ctx.client, ctx.room_id, "Jido send_text #{ctx.nonce}", format: :plain)
    assert sent.type == Jido.Chat.SendMessage.Completed.type()
    assert_round_trip(sent, Jido.Chat.SendMessage)
    cleanup(ctx, sent.data["result"]["id"])

    bytes = "Jido send_file #{ctx.nonce}\n"
    source = %{"content_base64" => Base.encode64(bytes), "filename" => "jido-text-api.txt"}
    assert {:ok, uploaded} = Jido.Chat.send_file(ctx.client, ctx.room_id, source, caption: "Public send_file")
    assert uploaded.type == Jido.Chat.SendFile.Completed.type()
    assert_round_trip(uploaded, Jido.Chat.SendFile)
    cleanup(ctx, uploaded.data["result"]["id"])
    [media] = uploaded.data["result"]["media"]
    downloaded = run(ctx, Jido.Chat.DownloadFile, %{"resource_ref" => media["resource_ref"]})
    assert Base.decode64!(downloaded["content_base64"]) == bytes
  end

  test "public stream_text selects rich drafts and persists the final message", ctx do
    chunks = ["**Jido stream_text", " verified** #{ctx.nonce}"]

    assert {:ok, completed} =
             Jido.Chat.stream_text(ctx.client, ctx.room_id, chunks, format: :markdown, update_interval_ms: 0)

    assert completed.type == Jido.Chat.StreamText.Completed.type()
    assert_round_trip(completed, Jido.Chat.StreamText)
    cleanup(ctx, completed.data["result"]["id"])
    assert_receive {:telegram_response, "sendRichMessageDraft", first, {:ok, true}}
    assert_receive {:telegram_response, "sendRichMessageDraft", second, {:ok, true}}
    assert first["draft_id"] == second["draft_id"]
    assert first["rich_message"] == %{"markdown" => "**Jido stream\\_text**"}
    assert_receive {:telegram_response, "sendRichMessage", final, {:ok, raw}}
    assert final["rich_message"] == %{"markdown" => Enum.join(chunks)}
    assert field(raw, "rich_message")
    refute_receive {:telegram_response, "editMessageText", _, _}
  end

  test "public stream_text can select send and edit for the same private chat", ctx do
    text = "Jido edit stream #{ctx.nonce}"

    assert {:ok, completed} =
             Jido.Chat.stream_text(ctx.client, ctx.room_id, ["Jido edit stream ", ctx.nonce],
               update_interval_ms: 0,
               options: [stream_delivery: :edit]
             )

    assert completed.type == Jido.Chat.StreamText.Completed.type()
    assert completed.data["result"]["text"] == text
    cleanup(ctx, completed.data["result"]["id"])
    assert_receive {:telegram_response, "sendMessage", first, {:ok, _}}
    assert first["text"] == "Jido edit stream "
    assert_receive {:telegram_response, "editMessageText", edit, {:ok, raw}}
    assert edit["text"] == text
    assert to_string(field(raw, "message_id")) == completed.data["result"]["id"]
    refute_receive {:telegram_response, "sendMessageDraft", _, _}
  end

  test "finite rendering and SendMessage send one final message without hidden draft writes", ctx do
    result =
      run(ctx, Jido.Chat.SendMessage, %{
        "room_id" => ctx.room_id,
        "text" => Jido.Chat.Markdown.StreamRenderer.render(["Jido finite ", "stream ", ctx.nonce])
      })

    cleanup(ctx, result["id"])
    assert result["text"] == "Jido finite stream #{ctx.nonce}"
    assert_receive {:telegram_response, "sendMessage", _, {:ok, _}}
    refute_receive {:telegram_response, "sendMessageDraft", _, _}
    refute_receive {:telegram_response, "sendRichMessageDraft", _, _}
  end

  test "explicit draft Actions and final send compose in native Flow", ctx do
    draft_id = System.unique_integer([:positive])

    first =
      command(ctx, Telegram.SendDraft, %{
        "room_id" => ctx.room_id,
        "draft_id" => draft_id,
        "text" => "Jido draft #{ctx.nonce}"
      })

    second =
      command(ctx, Telegram.SendDraft, %{
        "room_id" => ctx.room_id,
        "draft_id" => draft_id,
        "text" => "Jido draft complete #{ctx.nonce}"
      })

    finish =
      command(ctx, Jido.Chat.SendMessage, %{"room_id" => ctx.room_id, "text" => "Jido draft complete #{ctx.nonce}"})

    assert {:ok, %{first: a, second: b, signal: sent}} =
             Jido.Exec.run(
               DraftFlow,
               %{first: first.data, second: second.data, finish: finish.data},
               %{client: ctx.client},
               max_attempts: 1
             )

    assert a["result"]["acknowledged"]
    assert b["result"]["draft_id"] == draft_id
    cleanup(ctx, sent["result"]["id"])
  end

  test "rich send, reply, edit, and finite stream use the Signal boundary", ctx do
    root = send_message(ctx, "Jido rich root #{ctx.nonce}")

    reply =
      run(ctx, Jido.Chat.SendMessage, %{
        "room_id" => ctx.room_id,
        "text" => "## Jido rich\n\n| Check | Result |\n| --- | --- |\n| send | pass |",
        "format" => "markdown",
        "reply_to_id" => root["id"]
      })

    cleanup(ctx, reply["id"])
    raw = raw_response("sendRichMessage")
    assert field(raw, "rich_message")
    assert to_string(field(field(raw, "reply_to_message"), "message_id")) == root["id"]

    edited =
      run(
        ctx,
        Jido.Chat.EditMessage,
        %{
          "room_id" => ctx.room_id,
          "message_id" => reply["id"],
          "text" => "<h2>Jido rich edit passed</h2>",
          "format" => "html"
        }
      )

    assert edited["id"] == reply["id"]
    assert field(raw_response("editMessageText"), "rich_message")

    streamed =
      run(ctx, Jido.Chat.SendMessage, %{
        "room_id" => ctx.room_id,
        "text" => Jido.Chat.Markdown.StreamRenderer.render(["## Jido rich stream", "\n\nCompleted."]),
        "format" => "markdown"
      })

    cleanup(ctx, streamed["id"])
    assert field(raw_response("sendRichMessage"), "rich_message")
  end

  test "reply continuity retains the actual provider reply metadata", ctx do
    root = send_message(ctx, "Jido reply root #{ctx.nonce}")
    raw_response("sendMessage")

    reply =
      run(ctx, Jido.Chat.SendMessage, %{
        "room_id" => ctx.room_id,
        "text" => "Jido reply child #{ctx.nonce}",
        "reply_to_id" => root["id"]
      })

    cleanup(ctx, reply["id"])
    raw = raw_response("sendMessage")
    assert to_string(field(field(raw, "reply_to_message"), "message_id")) == root["id"]
    assert to_string(field(field(raw, "chat"), "id")) == ctx.room_id
  end

  test "native reaction Actions add and remove a real reaction", ctx do
    sent = send_message(ctx, "Jido reaction #{ctx.nonce}")
    data = %{"room_id" => ctx.room_id, "message_id" => sent["id"], "reaction" => @reaction}
    assert run(ctx, Jido.Chat.AddReaction, data) == %{"acknowledged" => true}
    assert run(ctx, Jido.Chat.RemoveReaction, data) == %{"acknowledged" => true}
  end

  test "document upload, metadata, and DownloadFile preserve exact JSON bytes", ctx do
    bytes = Jason.encode!(%{"sdk" => "jido", "nonce" => ctx.nonce})

    result =
      run(ctx, Telegram.SendDocument, %{
        "room_id" => ctx.room_id,
        "source" => upload(bytes, "jido-live.json"),
        "caption" => "Jido JSON #{ctx.nonce}"
      })

    cleanup(ctx, result["id"])
    ref = result["resource_ref"]
    info = run(ctx, Telegram.GetFile, %{"resource_ref" => ref})
    assert info["resource_ref"] == ref
    assert is_binary(info["file_path"])
    fetched = run(ctx, Jido.Chat.DownloadFile, %{"resource_ref" => ref})
    assert Base.decode64!(fetched["content_base64"]) == bytes
    assert Jason.decode!(Base.decode64!(fetched["content_base64"]))["sdk"] == "jido"
  end

  test "photo, sticker, animation, and video note Actions normalize and download", ctx do
    for {action, fixture, media_field, kind, width, height} <- [
          {Telegram.SendPhoto, "photo.png.b64", "photo", "image", 64, 64},
          {Telegram.SendSticker, "static-sticker.webp.b64", "sticker", "image", 512, 512},
          {Telegram.SendAnimation, "square-video.mp4.b64", "animation", "video", 240, 240},
          {Telegram.SendVideoNote, "square-video.mp4.b64", "video_note", "video", 240, 240}
        ] do
      result =
        run(ctx, action, %{
          "room_id" => ctx.room_id,
          "source" => upload(fixture(fixture), String.replace_suffix(fixture, ".b64", ""))
        })

      cleanup(ctx, result["id"])

      method =
        %{
          Telegram.SendPhoto => "sendPhoto",
          Telegram.SendSticker => "sendSticker",
          Telegram.SendAnimation => "sendAnimation",
          Telegram.SendVideoNote => "sendVideoNote"
        }[action]

      raw = raw_response(method)
      assert field(raw, media_field)
      assert {:ok, %{signals: [fact]}} = Jido.Chat.normalize(ctx.client, %{message: raw})
      assert fact.type == Signal.MessageReceived.type()
      assert [media] = fact.data["media"]
      assert media["kind"] == kind
      assert media["width"] == width
      assert media["height"] == height

      if media_field == "sticker",
        do: assert(media["metadata"]["telegram"] == %{"is_animated" => false, "is_video" => false})

      if media_field == "video_note", do: assert(media["duration"] == 1)
      fetched = run(ctx, Jido.Chat.DownloadFile, %{"resource_ref" => media["resource_ref"]})
      assert byte_size(Base.decode64!(fetched["content_base64"])) > 0
    end
  end

  test "SendFile accepts an explicit local file reference", ctx do
    path = Path.join(System.tmp_dir!(), "jido-live-#{ctx.nonce}.txt")
    File.write!(path, "Jido local upload #{ctx.nonce}")
    on_exit(fn -> File.rm(path) end)

    sent =
      run(ctx, Jido.Chat.SendFile, %{
        "room_id" => ctx.room_id,
        "source" => %{"client_id" => ctx.client.id, "kind" => "file", "id" => path}
      })

    cleanup(ctx, sent["id"])
    assert is_binary(sent["id"])
    assert [media] = sent["media"]
    fetched = run(ctx, Jido.Chat.DownloadFile, %{"resource_ref" => media["resource_ref"]})
    assert Base.decode64!(fetched["content_base64"]) == File.read!(path)
  end

  test "Telegram poll extension runs through Router and Dispatch", ctx do
    request =
      command(ctx, Telegram.SendPoll, %{
        "room_id" => ctx.room_id,
        "question" => "Jido live poll #{ctx.nonce}",
        "options" => ["Actions", "Signals"]
      })

    router =
      Jido.Signal.Router.new!([{Telegram.Signal.SendPoll, Jido.Instruction.template(:action, Telegram.SendPoll)}])

    assert {:ok, [template]} = Jido.Signal.Router.route(router, request)

    assert {:ok, instruction} =
             Jido.Instruction.bind(template, request.data, %{client: ctx.client, signal: request})

    assert {:ok, result} = Jido.Exec.run(instruction)
    assert {:ok, completed} = Telegram.SendPoll.reply(request, result, source: ctx.client.source)
    assert completed.type == Telegram.SendPoll.Completed.type()
    assert is_binary(completed.data["result"]["poll_id"])
    cleanup(ctx, completed.data["result"]["id"])
    assert :ok = Jido.Signal.Dispatch.dispatch(completed, {:pid, [target: self()]})
    assert_receive {:signal, ^completed}
    assert_round_trip(completed, Telegram.SendPoll)
  end

  if @forum_chat_id not in [nil, ""] do
    test "CreateThread creates a real forum topic and routes its message", ctx do
      forum = %{ctx | room_id: @forum_chat_id}

      topic =
        run(forum, Jido.Chat.CreateThread, %{
          "room_id" => @forum_chat_id,
          "name" => "Jido live #{ctx.nonce}"
        })

      sent =
        run(forum, Jido.Chat.SendMessage, %{
          "room_id" => @forum_chat_id,
          "thread_id" => topic["id"],
          "text" => "Jido topic #{ctx.nonce}"
        })

      cleanup(forum, sent["id"])
      assert to_string(field(raw_response("sendMessage"), "message_thread_id")) == topic["id"]
    end
  else
    test "CreateThread rejects a non-forum chat with a failure Signal", ctx do
      request =
        command(ctx, Jido.Chat.CreateThread, %{
          "room_id" => ctx.room_id,
          "name" => "Jido invalid forum"
        })

      assert {:error, %Jido.Chat.Error{signal: failed}} =
               Jido.Chat.Telegram.ActionHelpers.execute(Jido.Chat.CreateThread, request, %{client: ctx.client},
                 max_attempts: 1
               )

      assert failed.type == Jido.Chat.CreateThread.Failed.type()
      assert failed.data["code"] == "provider_failure"
      assert failed.data["outcome"] == "rejected"
      assert_round_trip(failed, Jido.Chat.CreateThread)
    end
  end

  if not @run_live_ui do
    @tag skip: "set RUN_LIVE_TELEGRAM_UI_TESTS=true for the manual Desktop callback test"
  end

  test "fresh Desktop callback becomes a Signal and is answered by an Action", ctx do
    value = "jido:verify:#{ctx.nonce}"

    keyboard = %{"rows" => [[%{"text" => "Verify Jido SDK", "value" => value}]]}

    sent =
      run(ctx, Jido.Chat.SendMessage, %{
        "room_id" => ctx.room_id,
        "text" => "Jido Desktop live check #{ctx.nonce}",
        "keyboard" => keyboard
      })

    cleanup(ctx, sent["id"])
    IO.puts("\nDESKTOP CALLBACK READY: Verify Jido SDK (#{ctx.nonce})\n")
    fact = await_callback(ctx, value, nil, System.monotonic_time(:millisecond) + @callback_timeout_ms)
    assert fact.type == Signal.ActionReceived.type()
    assert fact.data["room_id"] == ctx.room_id

    answer =
      run(ctx, Telegram.AnswerCallbackQuery, %{
        "interaction_id" => fact.data["interaction_id"],
        "text" => "Jido Action and Signal verified",
        "show_alert" => true
      })

    assert answer["answered"]

    run(ctx, Jido.Chat.EditMessage, %{
      "room_id" => ctx.room_id,
      "message_id" => sent["id"],
      "text" => "Verified: Jido Action and Signal received your click (#{ctx.nonce})",
      "keyboard" => %{"rows" => []}
    })

    assert :ok = Jido.Signal.Dispatch.dispatch(fact, {:pid, [target: self()]})
    assert_receive {:signal, ^fact}
    bus = start_supervised!({Jido.Signal.Bus, name: :telegram_live_events})
    assert {:ok, _} = Jido.Signal.Bus.subscribe(bus, "jido.chat.action.received")
    assert {:ok, [_]} = Jido.Signal.Bus.publish(bus, [fact])
  end

  defp await_callback(ctx, value, offset, deadline) do
    assert System.monotonic_time(:millisecond) < deadline,
           "Click Verify Jido SDK in Telegram Desktop within #{div(@callback_timeout_ms, 1000)} seconds"

    data = %{"timeout" => 2, "limit" => 100, "allowed_updates" => []}
    data = if offset, do: Map.put(data, "offset", offset), else: data
    result = run(ctx, Telegram.FetchUpdates, data)

    facts =
      Enum.map(result["signals"], fn wire ->
        {:ok, fact} = Jido.Signal.Catalog.decode(Jido.Chat.catalog(), Jason.encode!(wire))
        fact
      end)

    Enum.find(facts, &(&1.type == Signal.ActionReceived.type() and &1.data["value"] == value)) ||
      await_callback(ctx, value, result["next_offset"], deadline)
  end

  defp command(ctx, action, data) do
    data =
      if @thread_id not in [nil, ""] and
           action in [
             Jido.Chat.SendMessage,
             Jido.Chat.SendFile,
             Jido.Chat.StartTyping,
             Telegram.SendPhoto,
             Telegram.SendDocument,
             Telegram.SendSticker,
             Telegram.SendAnimation,
             Telegram.SendVideoNote,
             Telegram.SendPoll,
             Telegram.SendDraft
           ],
         do: Map.put_new(data, "thread_id", @thread_id),
         else: data

    action.signal_definition().new!(
      Map.merge(
        %{"client_id" => ctx.client.id, "request_id" => "#{ctx.nonce}:#{System.unique_integer([:positive])}"},
        data
      )
    )
  end

  defp run(ctx, action, data, opts \\ []) do
    request = command(ctx, action, data)

    assert {:ok, %{signal: completed}} =
             Jido.Chat.Telegram.ActionHelpers.execute(action, request, %{client: ctx.client, options: opts},
               max_attempts: 1
             )

    assert completed.data["client_id"] == ctx.client.id
    assert completed.data["request_id"] == request.data["request_id"]
    assert completed.extensions["jidocausationid"] == request.id
    assert_round_trip(completed, action)
    completed.data["result"]
  end

  defp assert_round_trip(signal, action) do
    catalog = Jido.Signal.Catalog.new!(Enum.uniq(Jido.Chat.signal_definitions() ++ action.signal_definitions()))
    assert {:ok, json} = Jido.Signal.Codec.serialize(signal)
    assert {:ok, ^signal} = Jido.Signal.Catalog.decode(catalog, json)
    refute json =~ to_string(@token)
  end

  defp send_message(ctx, text) do
    result = run(ctx, Jido.Chat.SendMessage, %{"room_id" => ctx.room_id, "text" => text})
    cleanup(ctx, result["id"])
    result
  end

  defp cleanup(ctx, id) do
    on_exit(fn ->
      request =
        Signal.DeleteMessage.new!(%{
          "client_id" => ctx.client.id,
          "request_id" => "cleanup:#{id}",
          "room_id" => ctx.room_id,
          "message_id" => id
        })

      Jido.Chat.execute(ctx.client, request)
    end)
  end

  defp raw_response(method) do
    assert_receive {:telegram_response, ^method, _, {:ok, raw}}, 2_000
    raw
  end

  defp upload(bytes, filename), do: %{"content_base64" => Base.encode64(bytes), "filename" => filename}

  defp fixture("photo.png.b64") do
    Path.expand("../../../../examples/providers/telegram/photo.png.b64", __DIR__)
    |> fixture_bytes()
  end

  defp fixture(filename), do: Path.join(__DIR__, "fixtures/#{filename}") |> fixture_bytes()

  defp fixture_bytes(path), do: path |> File.read!() |> String.replace(~r/\s/, "") |> Base.decode64!()

  defp field(nil, _), do: nil

  defp field(map, key),
    do:
      Map.get(map, key) ||
        Enum.find_value(Map.to_list(map), fn {k, v} -> if is_atom(k) and Atom.to_string(k) == key, do: v end)
end
