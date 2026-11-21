defmodule Jido.Chat.Telegram.LiveActions do
  @moduledoc false
  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [on_exit: 1, start_supervised!: 1]
  import Jido.Chat.Telegram.LiveFixture, only: [cleanup: 2, field: 2, fixture_path: 1, forget_cleanup: 2]
  alias Jido.Chat.Signal
  alias Jido.Chat.Telegram

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

  def a01(ctx) do
    sent = run(ctx, Jido.Chat.SendMessage, %{"room_id" => ctx.room_id, "text" => "Jido live send #{ctx.nonce}"})
    cleanup(ctx, sent["id"])

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

    forget_cleanup(ctx, sent["id"])
  end

  def a02(ctx) do
    assert run(ctx, Jido.Chat.StartTyping, %{"room_id" => ctx.room_id}) == %{"acknowledged" => true}
    assert run(ctx, Jido.Chat.FetchMetadata, %{"room_id" => ctx.room_id})["id"] == ctx.room_id
    assert run(ctx, Jido.Chat.OpenDm, %{"user_id" => ctx.room_id})["id"] == ctx.room_id
    bot = run(ctx, Telegram.GetMe, %{})
    assert bot["is_bot"]
    assert is_binary(bot["username"])
  end

  def a03(ctx) do
    info = run(ctx, Telegram.GetWebhookInfo, %{})
    assert info["url"] == ""
    assert is_integer(info["pending_update_count"])
    assert info["has_custom_certificate"] == false
  end

  def a04(ctx) do
    assert {:ok, sent} = Jido.Chat.send_text(ctx.client, ctx.room_id, "Jido send_text #{ctx.nonce}", format: :plain)
    assert sent.type == Jido.Chat.SendMessage.Completed.type()
    assert_round_trip(ctx, sent, Jido.Chat.SendMessage)
    cleanup(ctx, sent.data["result"]["id"])

    bytes = "Jido send_file #{ctx.nonce}\n"
    source = %{"content_base64" => Base.encode64(bytes), "filename" => "jido-text-api.txt"}
    assert {:ok, uploaded} = Jido.Chat.send_file(ctx.client, ctx.room_id, source, caption: "Public send_file")
    assert uploaded.type == Jido.Chat.SendFile.Completed.type()
    assert_round_trip(ctx, uploaded, Jido.Chat.SendFile)
    cleanup(ctx, uploaded.data["result"]["id"])
    [media] = uploaded.data["result"]["media"]
    downloaded = run(ctx, Jido.Chat.DownloadFile, %{"resource_ref" => media["resource_ref"]})
    assert Base.decode64!(downloaded["content_base64"]) == bytes
  end

  def a05(ctx) do
    chunks = ["**Jido stream_text", " verified** #{ctx.nonce}"]

    assert {:ok, completed} =
             Jido.Chat.stream_text(ctx.client, ctx.room_id, chunks, format: :markdown, update_interval_ms: 0)

    assert completed.type == Jido.Chat.StreamText.Completed.type()
    assert_round_trip(ctx, completed, Jido.Chat.StreamText)
    cleanup(ctx, completed.data["result"]["id"])
    assert_receive {:telegram_live_wire, "sendRichMessageDraft", first, {:ok, true}}
    assert_receive {:telegram_live_wire, "sendRichMessageDraft", second, {:ok, true}}
    assert first["draft_id"] == second["draft_id"]
    assert first["rich_message"] == %{"markdown" => "**Jido stream\\_text**"}
    assert_receive {:telegram_live_wire, "sendRichMessage", final, {:ok, raw}}
    assert final["rich_message"] == %{"markdown" => Enum.join(chunks)}
    assert field(raw, "rich_message")
    refute_receive {:telegram_live_wire, "editMessageText", _, _}
  end

  def a06(ctx) do
    text = "Jido edit stream #{ctx.nonce}"

    assert {:ok, completed} =
             Jido.Chat.stream_text(ctx.client, ctx.room_id, ["Jido edit stream ", ctx.nonce],
               update_interval_ms: 0,
               options: [stream_delivery: :edit]
             )

    assert completed.type == Jido.Chat.StreamText.Completed.type()
    assert completed.data["result"]["text"] == text
    cleanup(ctx, completed.data["result"]["id"])
    assert_receive {:telegram_live_wire, "sendMessage", first, {:ok, _}}
    assert first["text"] == "Jido edit stream "
    assert_receive {:telegram_live_wire, "editMessageText", edit, {:ok, raw}}
    assert edit["text"] == text
    assert to_string(field(raw, "message_id")) == completed.data["result"]["id"]
    refute_receive {:telegram_live_wire, "sendMessageDraft", _, _}
  end

  def a07(ctx) do
    result =
      run(ctx, Jido.Chat.SendMessage, %{
        "room_id" => ctx.room_id,
        "text" => Jido.Chat.Markdown.StreamRenderer.render(["Jido finite ", "stream ", ctx.nonce])
      })

    cleanup(ctx, result["id"])
    assert result["text"] == "Jido finite stream #{ctx.nonce}"
    assert_receive {:telegram_live_wire, "sendMessage", _, {:ok, _}}
    refute_receive {:telegram_live_wire, "sendMessageDraft", _, _}
    refute_receive {:telegram_live_wire, "sendRichMessageDraft", _, _}
  end

  def a08(ctx) do
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

  def a09(ctx) do
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

  def a10(ctx) do
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

  def a11(ctx) do
    sent = send_message(ctx, "Jido reaction #{ctx.nonce}")
    data = %{"room_id" => ctx.room_id, "message_id" => sent["id"], "reaction" => ctx.reaction}
    assert run(ctx, Jido.Chat.AddReaction, data) == %{"acknowledged" => true}
    assert run(ctx, Jido.Chat.RemoveReaction, data) == %{"acknowledged" => true}
  end

  def a12(ctx) do
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

  def a13(ctx) do
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

  def a14(ctx) do
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

  def a15(ctx) do
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

    assert {:ok, result} = Jido.Exec.run(instruction, %{}, %{}, max_attempts: 1)
    assert {:ok, completed} = Telegram.SendPoll.reply(request, result, source: ctx.client.source)
    assert completed.type == Telegram.SendPoll.Completed.type()
    assert is_binary(completed.data["result"]["poll_id"])
    cleanup(ctx, completed.data["result"]["id"])
    assert :ok = Jido.Signal.Dispatch.dispatch(completed, {:pid, [target: self()]})
    assert_receive {:signal, ^completed}
    assert_round_trip(ctx, completed, Telegram.SendPoll)
  end

  def a16(%{forum_id: nil} = ctx) do
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
    assert_round_trip(ctx, failed, Jido.Chat.CreateThread)
    assert_receive {:telegram_live_wire, "createForumTopic", %{"chat_id" => room}, {:error, _}}
    assert room == ctx.room_id
  end

  def a16(ctx) do
    forum = %{ctx | room_id: ctx.forum_id}

    topic =
      run(forum, Jido.Chat.CreateThread, %{
        "room_id" => ctx.forum_id,
        "name" => "Jido live #{ctx.nonce}"
      })

    sent =
      run(forum, Jido.Chat.SendMessage, %{
        "room_id" => ctx.forum_id,
        "thread_id" => topic["id"],
        "text" => "Jido topic #{ctx.nonce}"
      })

    cleanup(forum, sent["id"])
    assert to_string(field(raw_response("sendMessage"), "message_thread_id")) == topic["id"]
  end

  def a17(ctx), do: exercise_callback(ctx, :replay)
  def a17_live(ctx), do: exercise_callback(ctx, :live)

  defp exercise_callback(ctx, mode) do
    value = "jido:verify:#{ctx.nonce}"
    label = if mode == :live, do: "Verify Jido SDK", else: "Automated check"
    keyboard = %{"rows" => [[%{"text" => label, "value" => value}]]}

    sent =
      run(ctx, Jido.Chat.SendMessage, %{
        "room_id" => ctx.room_id,
        "text" =>
          if(mode == :live, do: "Jido Desktop live check #{ctx.nonce}", else: "Jido callback replay #{ctx.nonce}"),
        "keyboard" => keyboard
      })

    cleanup(ctx, sent["id"])
    raw = raw_response("sendMessage")
    assert to_string(field(raw, "message_id")) == sent["id"]
    assert [[button]] = raw |> field("reply_markup") |> field("inline_keyboard")
    assert field(button, "callback_data") == value
    assert field(button, "text") == label

    {fact, answer_ctx} = callback(ctx, mode, raw, value)
    assert fact.type == Signal.ActionReceived.type()
    assert fact.data["room_id"] == ctx.room_id
    assert fact.data["message_id"] == sent["id"]
    assert fact.data["value"] == value

    answer =
      run(answer_ctx, Telegram.AnswerCallbackQuery, %{
        "interaction_id" => fact.data["interaction_id"],
        "text" => "Jido Action and Signal verified",
        "show_alert" => true
      })

    assert answer["answered"]
    assert answer["interaction_id"] == fact.data["interaction_id"]
    assert_answer(mode, answer["interaction_id"])

    text = "Verified: Jido Action and Signal processed the callback (#{ctx.nonce})"

    edited =
      run(ctx, Jido.Chat.EditMessage, %{
        "room_id" => ctx.room_id,
        "message_id" => sent["id"],
        "text" => text,
        "keyboard" => %{"rows" => []}
      })

    assert edited["id"] == sent["id"]
    assert edited["text"] == text
    assert_receive {:telegram_live_wire, "editMessageText", payload, {:ok, stored}}, 2_000
    assert payload["reply_markup"] == %{"inline_keyboard" => []}
    assert to_string(field(stored, "message_id")) == sent["id"]
    assert field(stored, "text") == text
    assert field(stored, "reply_markup") in [nil, %{"inline_keyboard" => []}]

    assert :ok = Jido.Signal.Dispatch.dispatch(fact, {:pid, [target: self()]})
    assert_receive {:signal, ^fact}
    bus = start_supervised!({Jido.Signal.Bus, name: :telegram_live_events})
    assert {:ok, _} = Jido.Signal.Bus.subscribe(bus, "jido.chat.action.received")
    assert {:ok, [_]} = Jido.Signal.Bus.publish(bus, [fact])
  end

  defp callback(ctx, :live, _message, value) do
    IO.puts("\nDESKTOP CALLBACK READY: Verify Jido SDK (#{ctx.nonce})\n")
    {await_callback(ctx, value, nil, System.monotonic_time(:millisecond) + ctx.callback_timeout_ms), ctx}
  end

  defp callback(ctx, :replay, message, value) do
    callback = %{
      "id" => "replay-#{ctx.nonce}",
      "data" => value,
      "from" => %{"id" => 1},
      "message" => message
    }

    replay_client = %{
      ctx.client
      | transport: __MODULE__.ReplayTransport,
        credentials: %{token: "telegram-replay-sentinel"},
        config: [callback_replay: callback, live_observer: self()]
    }

    replay = %{ctx | client: replay_client}
    assert {[fact], 2} = fetch_callbacks(replay, nil, 0)
    {fact, replay}
  end

  defp assert_answer(:replay, id) do
    assert_receive {:telegram_replay_answer,
                    %{"callback_query_id" => ^id, "show_alert" => true, "text" => "Jido Action and Signal verified"}}

    refute_received {:telegram_replay_answer, _}
    refute_received {:telegram_live_wire, "answerCallbackQuery", _, _}
  end

  defp assert_answer(:live, id) do
    assert_receive {:telegram_live_wire, "answerCallbackQuery", %{"callback_query_id" => ^id}, {:ok, true}}
  end

  defp await_callback(ctx, value, offset, deadline) do
    assert System.monotonic_time(:millisecond) < deadline,
           "Click Verify Jido SDK in Telegram Desktop within #{div(ctx.callback_timeout_ms, 1000)} seconds"

    {facts, next_offset} = fetch_callbacks(ctx, offset, 2)

    Enum.find(facts, &(&1.type == Signal.ActionReceived.type() and &1.data["value"] == value)) ||
      await_callback(ctx, value, next_offset, deadline)
  end

  defp fetch_callbacks(ctx, offset, timeout) do
    data = %{"timeout" => timeout, "limit" => 100, "allowed_updates" => []}
    data = if offset, do: Map.put(data, "offset", offset), else: data
    result = run(ctx, Telegram.FetchUpdates, data)

    facts =
      Enum.map(result["signals"], fn wire ->
        {:ok, fact} = Jido.Signal.Catalog.decode(Jido.Chat.catalog(), Jason.encode!(wire))
        fact
      end)

    {facts, result["next_offset"]}
  end

  defmodule ReplayTransport do
    @moduledoc false
    @behaviour Jido.Chat.Telegram.Transport

    @impl true
    def call("telegram-replay-sentinel", "getUpdates", %{"timeout" => 0}, opts) do
      {:ok, [%{"update_id" => 1, "callback_query" => Keyword.fetch!(opts, :callback_replay)}]}
    end

    def call("telegram-replay-sentinel", "answerCallbackQuery", %{"callback_query_id" => id} = payload, opts) do
      if id == Keyword.fetch!(opts, :callback_replay)["id"] do
        send(Keyword.fetch!(opts, :live_observer), {:telegram_replay_answer, payload})
        {:ok, true}
      else
        {:error, {:not_attempted, :invalid_replay}}
      end
    end

    def call(_, _, _, _), do: {:error, {:not_attempted, :invalid_replay}}
  end

  defp command(ctx, action, data) do
    data =
      if ctx.thread_id not in [nil, ""] and
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
         do: Map.put_new(data, "thread_id", ctx.thread_id),
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
    assert_round_trip(ctx, completed, action)
    completed.data["result"]
  end

  defp assert_round_trip(ctx, signal, action) do
    catalog = Jido.Signal.Catalog.new!(Enum.uniq(Jido.Chat.signal_definitions() ++ action.signal_definitions()))
    assert {:ok, json} = Jido.Signal.Codec.serialize(signal)
    assert {:ok, ^signal} = Jido.Signal.Catalog.decode(catalog, json)
    refute json =~ ctx.client.credentials.token
  end

  defp send_message(ctx, text) do
    result = run(ctx, Jido.Chat.SendMessage, %{"room_id" => ctx.room_id, "text" => text})
    cleanup(ctx, result["id"])
    result
  end

  defp raw_response(method) do
    assert_receive {:telegram_live_wire, ^method, _, {:ok, raw}}, 2_000
    raw
  end

  defp upload(bytes, filename), do: %{"content_base64" => Base.encode64(bytes), "filename" => filename}

  defp fixture(filename), do: filename |> fixture_path() |> fixture_bytes()

  defp fixture_bytes(path), do: path |> File.read!() |> String.replace(~r/\s/, "") |> Base.decode64!()
end
