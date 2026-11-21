defmodule Jido.Chat.Discord.Transport do
  @moduledoc "Private Discord REST boundary. Tokens and raw provider data stay here."
  @callback call(String.t(), atom(), String.t(), map() | {:multipart, map(), binary(), String.t()} | nil, keyword()) ::
              {:ok, term()} | {:error, term()}
end
