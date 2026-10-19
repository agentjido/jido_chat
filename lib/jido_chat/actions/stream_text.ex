defmodule Jido.Chat.StreamText do
  @moduledoc """
  Native streaming Action. Input and output are `%{signal: signal}`. Pass the
  client and lazy chunk source as `%{client: client, options: [stream: chunks]}`.
  The configured adapter owns delivery. Jido.Exec uses its temporary execution
  task; Jido Chat owns no worker or stored state. No retry is made.
  """
  use Jido.ChatAction, name: "chat_stream_text", signal: Jido.Chat.Signal.StreamText

  @impl Jido.ChatAction
  def invoke(client, signal, opts) do
    with {:ok, chunks} <- Keyword.fetch(opts, :stream),
         true <- not is_nil(Enumerable.impl_for(chunks)) do
      client.adapter.invoke(client, signal, opts)
    else
      _ -> {:error, {:not_attempted, :invalid_stream}}
    end
  end
end
