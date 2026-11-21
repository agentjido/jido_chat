defmodule Jido.Chat.Telegram.Transport do
  @moduledoc """
  Transport contract for Telegram Bot API calls.
  """

  @type api_result :: {:ok, map() | [map()] | boolean() | binary()} | {:error, term()}

  @doc "Perform a Telegram Bot API call for one client."
  @callback call(token :: String.t(), method :: String.t(), payload :: map(), opts :: keyword()) ::
              api_result()
end
