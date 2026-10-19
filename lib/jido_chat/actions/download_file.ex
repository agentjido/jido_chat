defmodule Jido.Chat.DownloadFile do
  @moduledoc "Native Jido Action for `Jido.Chat.Signal.DownloadFile`. Input and output use `%{signal: signal}`. Pass `%{client: client}` as context."
  use Jido.ChatAction, name: "chat_download_file", signal: Jido.Chat.Signal.DownloadFile
end
