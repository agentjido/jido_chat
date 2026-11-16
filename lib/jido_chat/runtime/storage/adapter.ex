defmodule Jido.Chat.Runtime.Storage.Adapter do
  @moduledoc """
  Declares the small Runtime storage capabilities implemented by an adapter.

  The declaration adds the selected capability behaviours. Storage remains a
  pair of `{adapter_module, resource}`, so the resource can be a process, an
  Ecto Repo configuration, Ash resources, or another host-owned value.
  """

  alias Jido.Chat.Runtime.Storage.{Commit, Links, Outbox}

  @capabilities [Links, Outbox, Commit]

  @doc "Declares storage capability behaviours on the calling module."
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    configured = Keyword.fetch!(opts, :capabilities)

    unless is_list(configured) do
      raise ArgumentError,
            "capabilities must be a unique non-empty list of Jido Chat storage capabilities"
    end

    capabilities = Enum.map(configured, &Macro.expand(&1, __CALLER__))

    unknown = capabilities -- @capabilities

    unless capabilities != [] and unknown == [] and
             length(capabilities) == length(Enum.uniq(capabilities)) do
      raise ArgumentError,
            "capabilities must be a unique non-empty list of Jido Chat storage capabilities"
    end

    behaviours =
      Enum.map(capabilities, fn capability ->
        quote do
          @behaviour unquote(capability)
        end
      end)

    quote do
      unquote_splicing(behaviours)

      @doc false
      @spec __storage_capabilities__() :: [module()]
      def __storage_capabilities__, do: unquote(capabilities)
    end
  end

  @doc "Returns every storage capability that an adapter can declare."
  @spec capabilities() :: [module()]
  def capabilities, do: @capabilities
end
