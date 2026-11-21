defmodule Jido.Chat.Slack.SocketMode.SocketClient do
  @moduledoc """
  Contract for the long-lived Socket Mode WebSocket connection.
  """

  @callback connect(url :: String.t(), owner :: pid(), opts :: keyword()) ::
              {:ok, term()} | {:error, term()}

  @callback send_text(socket :: term(), payload :: String.t()) :: :ok | {:error, term()}

  @callback close(socket :: term()) :: :ok | {:error, term()}
end
