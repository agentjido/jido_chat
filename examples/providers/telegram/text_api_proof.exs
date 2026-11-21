# Host-side example. It leaves four messages for inspection in Telegram Desktop.
unless System.get_env("RUN_LIVE_TELEGRAM_TESTS") in ["1", "true", "TRUE"] do
  raise "Set RUN_LIVE_TELEGRAM_TESTS=true to send the text API proof"
end

token = System.fetch_env!("TELEGRAM_BOT_TOKEN")
room = System.fetch_env!("TELEGRAM_TEST_CHAT_ID")
run_id = Integer.to_string(System.system_time(:second))
client = Jido.Chat.Client.new!(Jido.Chat.Telegram.Adapter, id: "telegram.text_api.proof", credentials: %{token: token})

{:ok, sent} = Jido.Chat.send_text(client, room, "Jido text API proof #{run_id}: send_text passed.")
IO.puts("send_text: #{sent.data["result"]["id"]}; run #{run_id}")

chunks =
  Stream.map(
    ["## Jido draft stream", "\n\nProof #{run_id}.", "\n\n**Draft previews and final send passed.**"],
    fn text ->
      Process.sleep(1200)
      text
    end
  )

{:ok, streamed} = Jido.Chat.stream_text(client, room, chunks, format: :markdown)
IO.puts("draft stream_text: #{streamed.data["result"]["id"]}; run #{run_id}")

chunks =
  Stream.map(["Jido edit stream", " proof #{run_id}.", " Send and edit passed."], fn text ->
    Process.sleep(1200)
    text
  end)

{:ok, edited} = Jido.Chat.stream_text(client, room, chunks, options: [stream_delivery: :edit])
IO.puts("edit stream_text: #{edited.data["result"]["id"]}; run #{run_id}")

source = %{
  "content_base64" => File.read!(Path.join(__DIR__, "photo.png.b64")) |> String.trim(),
  "filename" => "jido-text-api-proof.png"
}

{:ok, uploaded} =
  Jido.Chat.send_file(client, room, source, media_kind: :image, caption: "Jido send_file passed. Proof #{run_id}.")

IO.puts("send_file: #{uploaded.data["result"]["id"]}; run #{run_id}")

for signal <- [sent, streamed, edited, uploaded] do
  {:ok, json} = Jido.Signal.Codec.serialize(signal)
  {:ok, ^signal} = Jido.Signal.Catalog.decode(Jido.Chat.Telegram.catalog(), json)
end
