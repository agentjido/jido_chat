defmodule Jido.Chat.Runtime.Room.Reaction do
  @moduledoc "Durable current reaction state for one Room message and actor."

  alias Jido.Chat.Runtime.Data
  alias Jido.Chat.Runtime.Room.Membership

  @fields [
    :schema_version,
    :id,
    :room_id,
    :message_id,
    :reaction,
    :actor_key,
    :actor,
    :status,
    :revision,
    :inserted_at,
    :updated_at
  ]
  @statuses [:active, :removed]

  @enforce_keys @fields
  defstruct @fields

  @type status :: :active | :removed
  @type actor :: String.t() | map()
  @type t :: %__MODULE__{
          schema_version: 1,
          id: String.t(),
          room_id: String.t(),
          message_id: String.t(),
          reaction: String.t(),
          actor_key: String.t(),
          actor: actor(),
          status: status(),
          revision: pos_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @doc "Returns the supported reaction states."
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc "Builds one validated reaction record."
  @spec new(t() | map()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = value), do: value |> Map.from_struct() |> new()

  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    with attrs <- atomize(attrs),
         true <- Map.keys(attrs) -- @fields == [],
         attrs <- normalize_status(attrs),
         room_id <- Map.get(attrs, :room_id),
         message_id <- Map.get(attrs, :message_id),
         reaction <- Map.get(attrs, :reaction),
         true <- valid_id?(room_id) and valid_id?(message_id) and valid_reaction?(reaction),
         {:ok, actor, actor_key} <- portable_actor(room_id, Map.get(attrs, :actor)),
         id = identity_id(room_id, message_id, reaction, actor_key),
         true <- derived_field?(attrs, :id, id) and derived_field?(attrs, :actor_key, actor_key),
         {:ok, inserted_at} <- Data.datetime(Map.get(attrs, :inserted_at, now)),
         {:ok, updated_at} <- Data.datetime(Map.get(attrs, :updated_at, now)) do
      attrs =
        attrs
        |> Map.put_new(:schema_version, 1)
        |> Map.put(:id, id)
        |> Map.put(:actor, actor)
        |> Map.put(:actor_key, actor_key)
        |> Map.put_new(:status, :active)
        |> Map.put_new(:revision, 1)
        |> Map.put(:inserted_at, inserted_at)
        |> Map.put(:updated_at, updated_at)

      attrs |> then(&struct(__MODULE__, &1)) |> validate()
    else
      false -> {:error, :invalid_reaction}
      {:error, _reason} = error -> error
    end
  end

  def new(_value), do: {:error, :invalid_reaction}

  @doc "Builds one reaction record or raises."
  @spec new!(t() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, reaction} -> reaction
      {:error, reason} -> raise ArgumentError, "invalid Room reaction: #{inspect(reason)}"
    end
  end

  @doc "Builds the next current-state revision."
  @spec transition(t(), status()) :: {:ok, t()} | {:error, term()}
  def transition(%__MODULE__{status: status} = value, status), do: {:ok, value}

  def transition(%__MODULE__{} = value, status) when status in @statuses do
    value
    |> Map.from_struct()
    |> Map.merge(%{status: status, revision: value.revision + 1, updated_at: DateTime.utc_now()})
    |> new()
  end

  def transition(_value, _status), do: {:error, :invalid_reaction}

  @doc "Returns the actor value used by Room authorization and projections."
  @spec actor(t()) :: String.t() | Jido.Agent.Address.t()
  def actor(%__MODULE__{actor: actor}) when is_binary(actor), do: actor
  def actor(%__MODULE__{actor: actor}), do: Jido.Agent.Address.from_map!(actor)

  @doc "Returns the storage key for one reaction identity."
  @spec key(String.t(), String.t(), String.t(), term()) ::
          {:ok, {String.t(), String.t(), String.t(), String.t()}} | {:error, :invalid_reaction}
  def key(room_id, message_id, reaction, actor) do
    with {:ok, _actor, actor_key} <- portable_actor(room_id, actor),
         true <- valid_id?(room_id) and valid_id?(message_id) and valid_reaction?(reaction) do
      {:ok, {room_id, message_id, reaction, actor_key}}
    else
      _reason -> {:error, :invalid_reaction}
    end
  end

  @doc "Serializes one reaction record to portable data."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    %{
      "__type__" => "runtime_room_reaction",
      "schema_version" => value.schema_version,
      "id" => value.id,
      "room_id" => value.room_id,
      "message_id" => value.message_id,
      "reaction" => value.reaction,
      "actor_key" => value.actor_key,
      "actor" => value.actor,
      "status" => Atom.to_string(value.status),
      "revision" => value.revision,
      "inserted_at" => DateTime.to_iso8601(value.inserted_at),
      "updated_at" => DateTime.to_iso8601(value.updated_at)
    }
  end

  @doc "Restores one reaction record from portable data."
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()
  def from_map(_value), do: {:error, :invalid_reaction}

  defp validate(%__MODULE__{} = value) do
    valid =
      value.schema_version == 1 and valid_id?(value.id) and valid_id?(value.room_id) and
        valid_id?(value.message_id) and valid_reaction?(value.reaction) and
        value.id == identity_id(value.room_id, value.message_id, value.reaction, value.actor_key) and
        value.actor_key == Membership.key(value.actor) and value.status in @statuses and
        is_integer(value.revision) and value.revision > 0 and Data.utc?(value.inserted_at) and
        Data.utc?(value.updated_at) and DateTime.compare(value.updated_at, value.inserted_at) in [:eq, :gt]

    if valid, do: {:ok, value}, else: {:error, :invalid_reaction}
  end

  defp portable_actor(room_id, actor) do
    case Membership.new(%{room_id: room_id, member: actor}) do
      {:ok, membership} -> {:ok, membership.member, membership.member_key}
      {:error, _reason} -> {:error, :invalid_reaction_actor}
    end
  end

  defp identity_id(room_id, message_id, reaction, actor_key) do
    {room_id, message_id, reaction, actor_key}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  defp valid_id?(value), do: is_binary(value) and byte_size(value) in 1..256
  defp valid_reaction?(value), do: is_binary(value) and byte_size(value) in 1..256
  defp derived_field?(attrs, key, value), do: not Map.has_key?(attrs, key) or Map.get(attrs, key) == value

  defp normalize_status(attrs) do
    case Map.get(attrs, :status) do
      "active" -> Map.put(attrs, :status, :active)
      "removed" -> Map.put(attrs, :status, :removed)
      _other -> attrs
    end
  end

  defp atomize(attrs) do
    Enum.reduce(@fields, attrs, fn field, result ->
      string = Atom.to_string(field)

      if Map.has_key?(result, string) and not Map.has_key?(result, field) do
        result |> Map.put(field, Map.fetch!(result, string)) |> Map.delete(string)
      else
        Map.delete(result, string)
      end
    end)
  end
end
