defmodule Jido.Chat.Providers.Dependencies do
  @moduledoc false

  @doc false
  def req(module \\ Req)
  def req(Req), do: check(req: Req)
  def req(_custom), do: :ok

  @doc false
  def discord_gateway, do: check(mint: Mint.HTTP1, mint_web_socket: Mint.WebSocket)
  @doc false
  def slack_socket, do: check(websockex: WebSockex)
  @doc false
  def telegram, do: check(ex_gram: ExGram, req: Req)

  @doc false
  @spec check(keyword(module())) :: :ok | {:error, {:not_attempted, {:missing_dependency, atom()}}}
  def check(dependencies) do
    case Enum.find(dependencies, fn {_app, module} -> not Code.ensure_loaded?(module) end) do
      nil -> :ok
      {app, _module} -> {:error, {:not_attempted, {:missing_dependency, app}}}
    end
  end
end
