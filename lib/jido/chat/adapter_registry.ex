defmodule Jido.Chat.AdapterRegistry do
  @moduledoc false

  @spec normalize_adapters(map() | term()) :: map()
  def normalize_adapters(adapters) when is_map(adapters), do: adapters
  def normalize_adapters(_), do: %{}

  @spec resolve(map(), atom()) :: {:ok, module()} | {:error, {:unknown_adapter, atom()}}
  def resolve(chat, adapter_name) when is_map(chat) and is_atom(adapter_name) do
    adapters = Map.get(chat, :adapters, %{})

    case Map.fetch(adapters, adapter_name) do
      {:ok, adapter_module} -> {:ok, adapter_module}
      :error -> {:error, {:unknown_adapter, adapter_name}}
    end
  end

  @spec resolve!(map(), atom()) :: module()
  def resolve!(chat, adapter_name) when is_map(chat) and is_atom(adapter_name) do
    case resolve(chat, adapter_name) do
      {:ok, adapter_module} ->
        adapter_module

      {:error, {:unknown_adapter, _}} ->
        raise ArgumentError,
              "unknown adapter #{inspect(adapter_name)}; configure it in chat.adapters"
    end
  end
end
