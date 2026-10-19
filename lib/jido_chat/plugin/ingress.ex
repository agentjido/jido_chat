defmodule Jido.Chat.Plugin.Ingress do
  @moduledoc "Dispatch adapter for a named Chat connection on a Jido Agent."
  @behaviour Jido.Signal.Dispatch.Adapter

  @impl true
  def options_schema do
    Zoi.keyword([server: Zoi.pid() |> Zoi.required(), connection: Zoi.atom() |> Zoi.required()],
      unrecognized_keys: :error
    )
  end

  @impl true
  def deliver(signal, opts) do
    case Jido.Chat.Plugin.ingest(opts[:server], opts[:connection], signal) do
      {:ok, _agent, _directives} -> :ok
      {:error, _} = error -> error
    end
  end
end
