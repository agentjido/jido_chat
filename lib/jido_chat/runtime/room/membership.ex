defmodule Jido.Chat.Runtime.Room.Membership do
  @moduledoc "Durable membership state for one Room member."

  @statuses [:active, :suspended, :revoked]
  @fields [
    :schema_version,
    :room_id,
    :member_key,
    :member,
    :issuer,
    :status,
    :revision,
    :metadata,
    :joined_at,
    :ended_at,
    :inserted_at,
    :updated_at
  ]
  @enforce_keys @fields
  defstruct @fields

  @type status :: :active | :suspended | :revoked
  @type t :: %__MODULE__{}

  @doc "Returns the supported membership statuses."
  def statuses, do: @statuses

  @doc "Builds one validated membership."
  @spec new(map() | t()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = value), do: validate(value)

  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()
    attrs = atomize(attrs, @fields)

    with true <- Map.keys(attrs) -- @fields == [],
         {:ok, member} <- encode_member(Map.get(attrs, :member)),
         {:ok, issuer} <- encode_optional_member(Map.get(attrs, :issuer)),
         member_key = key(member) do
      attrs =
        attrs
        |> Map.put_new(:schema_version, 1)
        |> Map.put(:member, member)
        |> Map.put(:member_key, member_key)
        |> Map.put(:issuer, issuer)
        |> Map.put_new(:status, :active)
        |> Map.put_new(:revision, 1)
        |> Map.put_new(:metadata, %{})
        |> Map.put_new(:joined_at, now)
        |> Map.put_new(:ended_at, nil)
        |> Map.put_new(:inserted_at, now)
        |> Map.put_new(:updated_at, now)

      attrs |> then(&struct(__MODULE__, &1)) |> validate()
    else
      _ -> {:error, :invalid_membership}
    end
  end

  def new(_value), do: {:error, :invalid_membership}

  @doc "Builds one membership or raises."
  def new!(attrs), do: unwrap!(new(attrs))

  @doc "Builds the next status revision."
  @spec transition(t(), status(), term()) :: {:ok, t()} | {:error, term()}
  def transition(%__MODULE__{status: status} = value, status, _issuer), do: {:ok, value}

  def transition(%__MODULE__{} = value, status, issuer) when status in @statuses do
    with {:ok, issuer} <- encode_optional_member(issuer) do
      now = DateTime.utc_now()

      validate(%{
        value
        | status: status,
          issuer: issuer,
          revision: value.revision + 1,
          joined_at: if(status == :active, do: now, else: value.joined_at),
          ended_at: if(status == :active, do: nil, else: now),
          updated_at: now
      })
    end
  end

  def transition(_value, _status, _issuer), do: {:error, :invalid_membership}

  @doc "Returns the member value used by the Room Agent."
  @spec member(t()) :: String.t() | Jido.Agent.Address.t()
  def member(%__MODULE__{member: member}) when is_binary(member), do: member
  def member(%__MODULE__{member: member}), do: Jido.Agent.Address.from_map!(member)

  @doc "Returns one stable key for a portable member identity."
  @spec key(term()) :: String.t()
  def key(member) do
    member =
      case encode_member(member) do
        {:ok, portable} -> portable
        {:error, _reason} -> member
      end

    binary = :erlang.term_to_binary(member, [:deterministic])
    :sha256 |> :crypto.hash(binary) |> Base.url_encode64(padding: false)
  end

  defp validate(%__MODULE__{} = value) do
    valid =
      value.schema_version == 1 and valid_id?(value.room_id) and valid_id?(value.member_key) and
        value.member_key == key(value.member) and portable_member?(value.member) and
        (is_nil(value.issuer) or portable_member?(value.issuer)) and value.status in @statuses and
        is_integer(value.revision) and value.revision > 0 and portable?(value.metadata, 0) and
        utc?(value.joined_at) and (is_nil(value.ended_at) or utc?(value.ended_at)) and
        utc?(value.inserted_at) and utc?(value.updated_at)

    if valid, do: {:ok, value}, else: {:error, :invalid_membership}
  end

  defp encode_optional_member(nil), do: {:ok, nil}
  defp encode_optional_member(value), do: encode_member(value)
  defp encode_member(value) when is_binary(value) and value != "", do: {:ok, value}
  defp encode_member(%Jido.Agent.Address{} = value), do: Jido.Agent.Address.to_map(value)

  defp encode_member(%{"version" => 1} = value) do
    with {:ok, address} <- Jido.Agent.Address.from_map(value), do: Jido.Agent.Address.to_map(address)
  end

  defp encode_member(_value), do: {:error, :invalid_member}

  defp portable_member?(value) when is_binary(value), do: value != ""
  defp portable_member?(%{"version" => 1} = value), do: match?({:ok, _}, Jido.Agent.Address.from_map(value))
  defp portable_member?(_value), do: false

  defp valid_id?(value), do: is_binary(value) and byte_size(value) in 1..256
  defp utc?(%DateTime{utc_offset: 0, std_offset: 0}), do: true
  defp utc?(_value), do: false

  defp portable?(_value, depth) when depth > 16, do: false

  defp portable?(value, _depth)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value) or is_atom(value),
       do: true

  defp portable?(values, depth) when is_list(values),
    do: Enum.all?(values, &portable?(&1, depth + 1))

  defp portable?(value, depth) when is_map(value) and not is_struct(value) do
    keys = Map.keys(value)

    Enum.all?(keys, &(is_binary(&1) or is_atom(&1))) and
      length(Enum.map(keys, &to_string/1)) == length(Enum.uniq(Enum.map(keys, &to_string/1))) and
      Enum.all?(Map.values(value), &portable?(&1, depth + 1))
  end

  defp portable?(_value, _depth), do: false

  defp atomize(attrs, fields) do
    Enum.reduce(fields, attrs, fn field, result ->
      string = Atom.to_string(field)

      if Map.has_key?(result, string) and not Map.has_key?(result, field) do
        result |> Map.put(field, Map.fetch!(result, string)) |> Map.delete(string)
      else
        Map.delete(result, string)
      end
    end)
  end

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, reason}), do: raise(ArgumentError, "invalid Room membership: #{inspect(reason)}")
end
