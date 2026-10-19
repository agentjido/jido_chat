defmodule Jido.Chat.GetThreadParticipants do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.GetThreadParticipants`. Input and output use `%{signal: signal}`. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_get_thread_participants", signal: Jido.Chat.Signal.GetThreadParticipants
end
