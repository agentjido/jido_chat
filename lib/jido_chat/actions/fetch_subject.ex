defmodule Jido.Chat.FetchSubject do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.FetchSubject`. Input and output use `%{signal: signal}`. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_fetch_subject", signal: Jido.Chat.Signal.FetchSubject
end
