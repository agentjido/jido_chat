defmodule Jido.Chat.ID do
  @moduledoc """
  Lightweight ID generator for SDK structs.
  """

  @spec generate!() :: String.t()
  def generate! do
    "jch_" <> (16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false))
  end
end
