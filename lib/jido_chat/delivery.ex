defmodule Jido.Chat.Delivery do
  @moduledoc """
  One stable provider delivery identity and an ordered list of public facts.

  Build and validate the complete delivery before a sink starts authoritative
  processing. Transport acknowledgement and private resources are separate.
  """

  alias Jido.Chat.Client
  alias Jido.Chat.Signal.{Identity, Policy}
  alias Jido.Signal.Catalog

  @schema Zoi.struct(__MODULE__, %{
            id: Zoi.string() |> Zoi.min(1),
            signals: Zoi.list(Zoi.struct(Jido.Signal))
          })
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Builds a completely validated, ordered provider delivery."
  @spec new(Client.t(), String.t(), [Jido.Signal.t()]) :: {:ok, t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def new(client, id, signals), do: validate(client, %__MODULE__{id: id, signals: signals})

  @doc "Revalidates a delivery before direct sink acceptance."
  @spec validate(Client.t(), t()) :: {:ok, t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def validate(%Client{} = client, %__MODULE__{id: id, signals: signals} = delivery) do
    with true <- is_binary(id) and id != "" and String.valid?(id),
         true <- is_list(signals),
         :ok <- count_limit(signals),
         {:ok, validated} <- validate_signals(client, id, signals),
         :ok <- failure_limit(validated),
         :ok <- size_limit(id, validated) do
      {:ok, %{delivery | signals: validated}}
    else
      {:error, _} = error -> error
      _ -> Policy.error(:invalid_delivery)
    end
  rescue
    _ -> Policy.error(:invalid_delivery)
  catch
    _, _ -> Policy.error(:invalid_delivery)
  end

  def validate(_client, _delivery), do: Policy.error(:invalid_delivery)

  @doc false
  @spec validate_empty(t()) :: {:ok, t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def validate_empty(%__MODULE__{id: id, signals: []} = delivery) do
    with true <- is_binary(id) and id != "" and String.valid?(id),
         :ok <- size_limit(id, []) do
      {:ok, delivery}
    else
      {:error, _} = error -> error
      _ -> Policy.error(:invalid_delivery)
    end
  end

  def validate_empty(_delivery), do: Policy.error(:invalid_delivery)

  defp count_limit(signals) do
    if length(signals) <= 100, do: :ok, else: Policy.error(:too_many_signals)
  end

  defp failure_limit(signals) do
    if Enum.count(signals, &(&1.type == Jido.Chat.Signal.NormalizationFailed.type())) <= 20,
      do: :ok,
      else: Policy.error(:too_many_failures)
  end

  defp validate_signals(client, delivery_id, signals) do
    definitions = Jido.Chat.event_definitions(client)
    catalog = Jido.Chat.catalog(client)

    Enum.reduce_while(signals, {:ok, []}, fn signal, {:ok, acc} ->
      with {:ok, signal} <- Catalog.validate(catalog, signal),
           {:ok, signal} <- Policy.validate(signal),
           :ok <- fact_identity(client, delivery_id, definitions, signal) do
        {:cont, {:ok, [signal | acc]}}
      else
        {:error, %Jido.Chat.Errors.Contract{}} = error -> {:halt, error}
        _ -> {:halt, Policy.error(:invalid_delivery)}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp fact_identity(client, delivery_id, definitions, signal) do
    definition = Enum.find(definitions, &(&1.type() == signal.type and &1.dataschema() == signal.dataschema))

    subject =
      case signal.data["room_id"] do
        nil -> nil
        room_id -> Identity.conversation_subject(client.id, room_id)
      end

    if not is_nil(definition) and definition.__signal_kind__() == :fact and signal.source == client.source and
         signal.subject == subject and signal.data["delivery_id"] == delivery_id do
      :ok
    else
      Policy.error(:context_mismatch)
    end
  end

  defp size_limit(id, signals) do
    maps = Enum.map(signals, &Jido.Signal.to_map/1)
    encoded = Jason.encode!(%{"id" => id, "signals" => maps})
    if byte_size(encoded) <= 1_048_576, do: :ok, else: Policy.error(:delivery_too_large)
  end
end
