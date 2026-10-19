defmodule Jido.Chat.Client do
  @moduledoc """
  Immutable provider configuration. Construction starts no process and performs no I/O.

  Credentials and transport options stay in this local value. They never enter
  request or result Signals. The host loads credentials and selects transport policy.
  """
  alias Jido.Chat.Signal.{Identity, Policy}

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string() |> Zoi.refine({__MODULE__, :client_id, []}),
              adapter: Zoi.atom(),
              source: Zoi.string() |> Zoi.min(1),
              credentials: Zoi.map() |> Zoi.default(%{}),
              config: Zoi.any() |> Zoi.refine({__MODULE__, :keyword_config, []}) |> Zoi.default([]),
              transport: Zoi.atom() |> Zoi.nullable() |> Zoi.default(nil)
            },
            coerce: true
          )
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Builds an immutable client from explicit configuration."
  @spec new(module(), keyword()) :: {:ok, t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def new(adapter, opts) when is_atom(adapter) and is_list(opts) do
    with true <- Keyword.keyword?(opts),
         true <- length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))),
         true <- Keyword.keys(opts) -- [:id, :credentials, :config, :transport] == [],
         true <- Enum.all?([:credentials, :config], &(not Keyword.has_key?(opts, &1) or not is_nil(opts[&1]))),
         true <- Code.ensure_loaded?(adapter),
         true <-
           Enum.all?([channel_type: 0, capabilities: 0, invoke: 3, normalize: 3], fn {name, arity} ->
             function_exported?(adapter, name, arity)
           end),
         :ok <- Jido.Chat.Adapter.validate_capabilities(adapter),
         attrs = opts |> Map.new() |> Map.put(:adapter, adapter) |> Map.put(:source, Identity.client_source(opts[:id])),
         attrs = Map.put_new_lazy(attrs, :transport, fn -> default_transport(adapter) end),
         {:ok, client} <- Zoi.parse(@schema, attrs) do
      {:ok, client}
    else
      _ -> Policy.error(:invalid_client)
    end
  rescue
    _ -> Policy.error(:invalid_client)
  end

  def new(_, _), do: Policy.error(:invalid_client)

  @doc false
  def client_id(value, _opts) do
    Identity.client_source(value)
    :ok
  rescue
    _ -> {:error, "expected a non-empty UTF-8 client ID of at most 128 bytes"}
  end

  @doc false
  def keyword_config(value, _opts) do
    if is_list(value) and Keyword.keyword?(value), do: :ok, else: {:error, "expected keyword configuration"}
  end

  @doc "Builds a client or raises a contract error."
  @spec new!(module(), keyword()) :: t()
  def new!(adapter, opts) do
    case new(adapter, opts) do
      {:ok, client} -> client
      {:error, error} -> raise error
    end
  end

  @doc "Returns explicit private options for a provider helper. Do not place them in a Signal."
  @spec options(t()) :: keyword()
  def options(%__MODULE__{} = client) do
    client.config
    |> Keyword.merge(Enum.filter(client.credentials, fn {key, _} -> is_atom(key) end))
    |> Keyword.put(:transport, client.transport)
  end

  defp default_transport(adapter) do
    if function_exported?(adapter, :default_transport, 0), do: adapter.default_transport(), else: nil
  end
end

defimpl Inspect, for: Jido.Chat.Client do
  import Inspect.Algebra

  def inspect(client, opts) do
    concat(["#Jido.Chat.Client<", to_doc(%{id: client.id, adapter: client.adapter, source: client.source}, opts), ">"])
  end
end
