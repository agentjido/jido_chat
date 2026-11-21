defmodule Jido.Chat.Telegram.StreamRendererTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Markdown.StreamRenderer
  alias Jido.Chat.Telegram.Adapter

  @fixtures [
    {:split_emphasis, "Before **bold _and italic_** after"},
    {:split_link, "Read [the guide](https://jido.run/docs?q=chat) now."},
    {:list, "Plan:\n\n- first\n- second\n\nDone."},
    {:code_fence, "```elixir\nIO.puts(\"hello\")\n```\n\nDone."},
    {:structural_whitespace, "Heading\n\nParagraph  \nnext line\n\n"},
    {:empty_table_cells, "| Name |  | State |\n| --- | --- | --- |\n| alpha |  | ready |\n|  | beta |  |"}
  ]

  defmodule CapturingTransport do
    @behaviour Jido.Chat.Telegram.Transport

    @impl true
    def call(_token, method, payload, opts) do
      send(opts[:observer], {:telegram_call, method, payload})

      case method do
        draft when draft in ["sendMessageDraft", "sendRichMessageDraft"] ->
          {:ok, true}

        _send ->
          {:ok, %{"message_id" => 42, "chat" => %{"id" => payload["chat_id"]}, "date" => 1}}
      end
    end
  end

  test "finite rich streams preserve Markdown across arbitrary chunk boundaries" do
    for {name, markdown} <- @fixtures do
      assert {:ok, _} = stream(String.codepoints(markdown))
      assert [{"sendRichMessage", payload}] = collect_calls(), "unexpected provider writes for #{name}"
      assert payload["rich_message"] == %{"markdown" => markdown}
    end
  end

  test "structured chunks use deterministic Markdown and empty content makes no write" do
    chunks = [%{kind: :status, text: "Working"}, %{kind: :plan, payload: ["Inspect", "Change"]}]
    assert {:ok, _} = stream([StreamRenderer.render(chunks)])
    assert [{"sendRichMessage", payload}] = collect_calls()
    assert payload["rich_message"]["markdown"] == StreamRenderer.render(chunks)
    assert {:error, _} = stream(["", ""])
    assert collect_calls() == []
  end

  defp stream(chunks) do
    client =
      Jido.Chat.Client.new!(Adapter, id: "telegram", credentials: %{token: "bot-token"}, transport: CapturingTransport)

    with {:ok, request} <-
           Jido.Chat.Signal.Policy.new(Jido.Chat.Signal.SendMessage, %{
             "client_id" => client.id,
             "request_id" => "stream",
             "room_id" => "123",
             "text" => StreamRenderer.render(chunks),
             "format" => "markdown"
           }) do
      Jido.Chat.execute(client, request, options: [observer: self()])
    end
  end

  defp collect_calls(calls \\ []) do
    receive do
      {:telegram_call, method, payload} -> collect_calls([{method, payload} | calls])
    after
      0 -> Enum.reverse(calls)
    end
  end
end
