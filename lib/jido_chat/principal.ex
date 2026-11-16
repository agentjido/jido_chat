defmodule Jido.Chat.Principal do
  @moduledoc """
  A credential-free reference to an identity that can act in Chat.

  The host identity system remains the system of record. This value contains
  only the fields that Chat needs during admission and authorization.
  """

  @kinds [:human, :agent, :service, :system]
  @assurance_levels [:asserted, :verified]
  @fields [:id, :kind, :display_name, :roles, :assurance, :agent_address, :attributes]
  @private_keys ~w(raw credentials credential token access_token refresh_token password secret key proof)

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string() |> Zoi.min(1) |> Zoi.max(256),
              kind: Zoi.enum(@kinds),
              display_name: Zoi.string() |> Zoi.max(256) |> Zoi.nullish(),
              roles: Zoi.list(Zoi.string() |> Zoi.min(1) |> Zoi.max(128)) |> Zoi.max(64) |> Zoi.default([]),
              assurance: Zoi.enum(@assurance_levels) |> Zoi.default(:asserted),
              agent_address: Jido.Agent.Address.schema() |> Zoi.nullish(),
              attributes:
                Zoi.map()
                |> Zoi.refine({__MODULE__, :safe_attributes, []})
                |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Principal schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates a validated Principal."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = value), do: value |> Map.from_struct() |> new()

  def new(attrs) when is_map(attrs) do
    attrs
    |> Jido.Chat.Value.without_marker()
    |> Jido.Chat.Value.normalize_keys(@fields)
    |> Jido.Chat.Value.normalize_enum(:kind, @kinds)
    |> Jido.Chat.Value.normalize_enum(:assurance, @assurance_levels)
    |> normalize_agent_address()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Serializes the Principal without credentials or proof material."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    value = new(value)

    Jido.Chat.Value.plain_struct(value, "principal", %{
      agent_address: if(value.agent_address, do: Jido.Agent.Address.to_map!(value.agent_address))
    })
  end

  @doc "Restores a Principal from a portable map."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: new(map)

  @doc false
  def safe_attributes(value, _opts) do
    if safe_value?(value, 0), do: :ok, else: {:error, "attributes must not contain credentials or private values"}
  end

  defp safe_value?(_value, depth) when depth > 16, do: false
  defp safe_value?(value, _depth) when is_nil(value) or is_boolean(value) or is_number(value), do: true
  defp safe_value?(value, _depth) when is_binary(value), do: String.valid?(value)
  defp safe_value?(value, depth) when is_list(value), do: Enum.all?(value, &safe_value?(&1, depth + 1))

  defp safe_value?(value, depth) when is_map(value) and not is_struct(value) do
    Enum.all?(value, fn {key, item} ->
      safe_key?(key) and safe_value?(item, depth + 1)
    end)
  end

  defp safe_value?(_value, _depth), do: false

  defp safe_key?(key) when is_atom(key) or is_binary(key) do
    normalized = key |> to_string() |> String.downcase() |> String.replace(~r/[^a-z0-9]/u, "")
    Enum.all?(@private_keys, fn private -> not String.contains?(normalized, String.replace(private, "_", "")) end)
  end

  defp safe_key?(_key), do: false

  defp normalize_agent_address(%{agent_address: %Jido.Agent.Address{}} = attrs), do: attrs
  defp normalize_agent_address(%{agent_address: nil} = attrs), do: attrs

  defp normalize_agent_address(%{agent_address: %{"version" => 1} = value} = attrs) do
    case Jido.Agent.Address.from_map(value) do
      {:ok, address} -> Map.put(attrs, :agent_address, address)
      {:error, _reason} -> attrs
    end
  end

  defp normalize_agent_address(%{agent_address: value} = attrs) when is_map(value) do
    case Jido.Agent.Address.new(value) do
      {:ok, address} -> Map.put(attrs, :agent_address, address)
      {:error, _reason} -> attrs
    end
  end

  defp normalize_agent_address(attrs), do: attrs
end
