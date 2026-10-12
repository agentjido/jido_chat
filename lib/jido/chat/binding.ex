defmodule Jido.Chat.Binding do
  @moduledoc """
  A configured adapter binding with a stable public identity and private resources.

  Create it through `Jido.Chat.bind/2`. Transport, credentials, resource storage,
  and provider options stay in this local value. Do not encode this value as a
  public Signal. Resource storage ends when its owning process stops.
  """

  alias Jido.Chat.Signal.{Identity, Policy}

  @schema Zoi.struct(__MODULE__, %{
            id: Zoi.string() |> Zoi.min(1),
            adapter: Zoi.module(),
            source: Zoi.string(),
            options: Zoi.any(),
            resources: Zoi.any()
          })
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  @spec new(module(), keyword()) :: {:ok, t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def new(adapter, opts) when is_atom(adapter) and is_list(opts) do
    with true <- Keyword.keyword?(opts),
         true <- Code.ensure_loaded?(adapter),
         true <- function_exported?(adapter, :signal_protocol, 0),
         1 <- adapter.signal_protocol(),
         true <- function_exported?(adapter, :normalize_event, 2),
         true <- function_exported?(adapter, :configure_binding, 1),
         {:ok, _capabilities} <- Jido.Chat.Operations.Capabilities.read(adapter),
         id when is_binary(id) <- Keyword.get(opts, :id),
         source <- Identity.binding_source(id),
         {:ok, options} <- adapter.configure_binding(Keyword.delete(opts, :id)),
         true <- Keyword.keyword?(options) do
      {:ok,
       %__MODULE__{
         id: id,
         adapter: adapter,
         source: source,
         options: options,
         resources: :ets.new(:jido_chat_binding_resources, [:set, :public])
       }}
    else
      _ -> Policy.error(:incompatible_protocol, :adapter)
    end
  rescue
    _ -> Policy.error(:invalid_binding)
  catch
    _, _ -> Policy.error(:invalid_binding)
  end

  def new(_adapter, _opts), do: Policy.error(:invalid_binding)
end
