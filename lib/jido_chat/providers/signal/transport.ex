defmodule Jido.Chat.Signal.Transport do
  @moduledoc "Transport contract for signal-cli-backed calls."

  @callback send_message(String.t() | nil, String.t(), String.t(), keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback receive_messages(String.t() | nil, keyword()) :: {:ok, [map()]} | {:error, term()}

  @optional_callbacks receive_messages: 2
end
