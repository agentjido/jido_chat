defmodule Jido.Chat.Runtime.Storage.Bindings do
  @moduledoc """
  Storage capability for durable provider-to-Room bridge bindings.

  List results use ascending external Room ID order. `:after` is an exclusive
  external Room ID cursor. Limits are 1 through 1,000.
  """

  alias Jido.Chat.Runtime.Bridge.Binding

  @type query_option ::
          {:enabled, boolean()}
          | {:direction, Binding.direction()}
          | {:after, String.t()}
          | {:limit, pos_integer()}

  @callback insert_binding(term(), Binding.t()) :: {:ok, Binding.t()} | {:error, term()}
  @callback get_binding(term(), String.t(), String.t()) ::
              {:ok, Binding.t() | nil} | {:error, term()}
  @callback list_bindings(term(), String.t(), [query_option()]) ::
              {:ok, [Binding.t()]} | {:error, term()}
  @callback update_binding(term(), String.t(), String.t(), pos_integer(), Binding.t()) ::
              {:ok, Binding.t()} | {:error, term()}
end
