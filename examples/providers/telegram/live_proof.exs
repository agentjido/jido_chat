# Host-side example. It sends three test messages and leaves them in Telegram.
unless System.get_env("RUN_LIVE_TELEGRAM_TESTS") in ["1", "true", "TRUE"] do
  raise "Set RUN_LIVE_TELEGRAM_TESTS=true to send the Desktop proof"
end

defmodule Jido.Chat.Telegram.Example.DesktopProof do
  use Jido.Flow, name: "telegram_desktop_proof"

  flow do
    step("summary", action: Jido.Chat.SendMessage, params: %{signal: input(:summary)})
    step("photo", action: Jido.Chat.Telegram.SendPhoto, params: %{signal: input(:photo)}, needs: ["summary"])
    step("poll", action: Jido.Chat.Telegram.SendPoll, params: %{signal: input(:poll)}, needs: ["photo"])

    output(%{
      summary: result("summary", [:signal]),
      photo: result("photo", [:signal]),
      poll: result("poll", [:signal])
    })
  end
end

alias Jido.Chat.Telegram, as: Telegram

token = System.fetch_env!("TELEGRAM_BOT_TOKEN")
room = System.fetch_env!("TELEGRAM_TEST_CHAT_ID")
run_id = Integer.to_string(System.system_time(:second))
client = Jido.Chat.Client.new!(Telegram.Adapter, id: "telegram.desktop.proof", credentials: %{token: token})

request = fn action, data ->
  action.signal_definition().new!(
    Map.merge(
      %{
        "client_id" => client.id,
        "request_id" => "desktop:#{run_id}:#{action.name()}",
        "room_id" => room
      },
      data
    )
  )
end

summary =
  request.(Jido.Chat.SendMessage, %{
    "format" => "markdown",
    "keyboard" => %{
      "rows" => [[%{"text" => "Signal keyboard verified", "url" => "https://github.com/agentjido/jido_chat"}]]
    },
    "text" => """
    ## Jido SDK verified

    Proof run: #{run_id}

    | Primitive | Live proof |
    | --- | --- |
    | Action | Shared SendMessage + Telegram extensions |
    | Flow | Ordered summary, photo, poll |
    | Signal | Typed requests, results, and keyboard |
    | Router / Dispatch / Bus | Live integration tests passed |

    The host owns polling offsets, draft timing, and retries.
    """
  })

photo =
  request.(Telegram.SendPhoto, %{
    "source" => %{
      "content_base64" => File.read!(Path.join(__DIR__, "photo.png.b64")) |> String.trim(),
      "filename" => "jido-sdk-proof.png"
    },
    "caption" => "Jido native photo Action - proof #{run_id}"
  })

poll =
  request.(Telegram.SendPoll, %{
    "question" => "Jido SDK proof #{run_id}",
    "options" => ["Actions", "Flow", "Signals"]
  })

{:ok, outputs} =
  Jido.Exec.run(
    Jido.Chat.Telegram.Example.DesktopProof,
    %{summary: summary, photo: photo, poll: poll},
    %{client: client},
    max_attempts: 1
  )

for {step, signal} <- outputs do
  {:ok, json} = Jido.Signal.Codec.serialize(signal)
  {:ok, ^signal} = Jido.Signal.Catalog.decode(Telegram.catalog(), json)
  IO.puts("#{step}: #{signal.type}; message #{signal.data["result"]["id"]}")
end

IO.puts("Desktop proof run: #{run_id}")
