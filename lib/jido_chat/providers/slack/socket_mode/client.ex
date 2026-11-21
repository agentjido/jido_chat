defmodule Jido.Chat.Slack.SocketMode.Client do
  @moduledoc """
  Contract for opening Slack Socket Mode connections.
  """

  @callback open_socket(app_token :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}
end
