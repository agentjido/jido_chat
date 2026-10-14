defmodule Jido.Chat.Operations.Capabilities do
  @moduledoc false

  alias Jido.Chat.Operations.Definitions
  alias Jido.Chat.Signal.Policy
  @fallbacks [:post_message, :fetch_metadata, :fetch_thread, :post_channel_message, :stream]

  @doc false
  @spec read(module()) :: {:ok, map()} | {:error, Jido.Chat.Errors.Contract.t()}
  def read(adapter) do
    if Code.ensure_loaded?(adapter), do: read_loaded(adapter), else: Policy.error(:invalid_binding, :adapter)
  end

  defp read_loaded(adapter) do
    declared = if function_exported?(adapter, :capabilities, 0), do: adapter.capabilities(), else: %{}

    if is_map(declared) and Enum.all?(declared, fn {_key, value} -> value in [:native, :fallback, :unsupported] end) do
      matrix =
        Map.new(Definitions.all(), fn {_type, {_module, operation, fields, _shape, _schema}} ->
          arity = if operation == :load_options, do: 2, else: length(fields) + 1

          fallback =
            if operation in @fallbacks or
                 (operation == :fetch_subject and function_exported?(adapter, :fetch_thread, 2)),
               do: :fallback,
               else: :unsupported

          status =
            Map.get(declared, operation, if(function_exported?(adapter, operation, arity), do: :native, else: fallback))

          {operation, status}
        end)

      if Enum.all?(Definitions.all(), fn {_type, {_module, operation, fields, _shape, _schema}} ->
           arity = if operation == :load_options, do: 2, else: length(fields) + 1
           matrix[operation] != :native or function_exported?(adapter, operation, arity)
         end), do: {:ok, Map.merge(declared, matrix)}, else: Policy.error(:invalid_binding, :capabilities)
    else
      Policy.error(:invalid_binding, :capabilities)
    end
  end
end
