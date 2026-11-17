defmodule Jido.Chat.Runtime.Bus do
  @moduledoc """
  Application-wide observation Bus for one optional managed Chat Runtime.

  Room storage remains authoritative. This Bus carries the same committed
  Signals that Rooms publish. A host can subscribe to those Signals and then
  read the durable projection.
  """

  @default_max_log_size 10_000

  @doc false
  @spec child_spec(module(), pos_integer()) :: Supervisor.child_spec()
  def child_spec(runtime, max_log_size \\ @default_max_log_size) do
    Jido.Signal.Bus.child_spec(
      name: name(runtime),
      jido: runtime.jido(),
      max_log_size: max_log_size
    )
  end

  @doc "Returns the running Runtime Bus."
  @spec whereis(module()) :: {:ok, pid()} | {:error, :runtime_not_started}
  def whereis(runtime) when is_atom(runtime) and runtime not in [nil, true, false] do
    if function_exported?(runtime, :jido, 0) do
      case Jido.Signal.Bus.whereis(name(runtime), jido: runtime.jido()) do
        {:ok, bus} -> if Process.alive?(bus), do: {:ok, bus}, else: {:error, :runtime_not_started}
        {:error, :not_found} -> {:error, :runtime_not_started}
      end
    else
      {:error, :runtime_not_started}
    end
  end

  def whereis(_runtime), do: {:error, :runtime_not_started}

  @doc "Subscribes a target to native Jido Signal paths on the Runtime Bus."
  @spec subscribe(module(), Jido.Signal.Router.path(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def subscribe(runtime, path, opts \\ []) do
    with {:ok, bus} <- whereis(runtime),
         do: Jido.Signal.Bus.subscribe(bus, path, opts)
  end

  @doc "Unsubscribes one native Jido Signal Bus subscription."
  @spec unsubscribe(module(), String.t(), keyword()) :: :ok | {:error, term()}
  def unsubscribe(runtime, subscription_id, opts \\ []) do
    with {:ok, bus} <- whereis(runtime),
         do: Jido.Signal.Bus.unsubscribe(bus, subscription_id, opts)
  end

  @doc false
  @spec notify(module() | nil, Jido.Signal.t()) :: :ok
  def notify(nil, %Jido.Signal{}), do: :ok

  def notify(runtime, %Jido.Signal{} = signal) do
    with {:ok, bus} <- whereis(runtime),
         {:ok, _records} <- Jido.Signal.Bus.publish(bus, [signal]) do
      :ok
    else
      {:error, _reason} -> :ok
    end
  end

  @doc false
  @spec name(module()) :: String.t()
  def name(runtime) when is_atom(runtime) and runtime not in [nil, true, false] do
    "jido.chat.runtime/" <> Atom.to_string(runtime)
  end
end
