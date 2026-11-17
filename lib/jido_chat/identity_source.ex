defmodule Jido.Chat.IdentitySource do
  @moduledoc """
  A provider-scoped external identity assertion.

  The complete identity key is `{provider, account_id, external_id}`. Equal
  external IDs from different provider accounts are not the same identity.
  This value contains no provider credential or proof.
  """

  @fields [:provider, :account_id, :external_id, :room_id, :metadata]
  @schema Jido.Joi.struct(
            __MODULE__,
            %{
              provider: Jido.Joi.string() |> Jido.Joi.min(1) |> Jido.Joi.max(128),
              account_id: Jido.Joi.string() |> Jido.Joi.min(1) |> Jido.Joi.max(256),
              external_id: Jido.Joi.string() |> Jido.Joi.min(1) |> Jido.Joi.max(512),
              room_id:
                Jido.Joi.string()
                |> Jido.Joi.min(1)
                |> Jido.Joi.max(2_048)
                |> Jido.Joi.nullable()
                |> Jido.Joi.optional(),
              metadata:
                Jido.Joi.map()
                |> Jido.Joi.refine({Jido.Chat.Principal, :safe_attributes, []})
                |> Jido.Joi.default(%{})
            },
            coerce: true
          )
          |> Jido.Joi.refine({Jido.Chat.Wire, :portable, []})

  @type t :: unquote(Jido.Joi.type_spec(@schema))
  @enforce_keys Jido.Joi.enforce_keys(@schema)
  defstruct Jido.Joi.struct_fields(@schema)

  @doc "Returns the IdentitySource schema."
  @spec schema() :: Jido.Joi.schema()
  def schema, do: @schema

  @doc "Creates a validated provider-scoped identity source."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = value), do: value |> Map.from_struct() |> new()

  def new(attrs) when is_map(attrs) do
    attrs
    |> Jido.Chat.Value.without_marker()
    |> Jido.Chat.Value.normalize_keys(@fields)
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Returns the complete provider account identity key."
  @spec key(t()) :: {String.t(), String.t(), String.t()}
  def key(%__MODULE__{} = source), do: {source.provider, source.account_id, source.external_id}

  @doc "Serializes the identity source to a portable map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value), do: Jido.Chat.Value.plain_struct(new(value), "identity_source")

  @doc "Restores an identity source from a portable map."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: new(map)

  @doc false
  @spec from_signal(Jido.Chat.Client.t(), Jido.Signal.t()) :: {:ok, t()} | {:error, atom()}
  def from_signal(%Jido.Chat.Client{} = client, %Jido.Signal{type: type, data: data}) when is_map(data) do
    external_id = get_in(data, ["sender", "id"]) || data["actor_id"]
    room_id = data["room_id"]

    if is_binary(external_id) and external_id != "" do
      provider = client.adapter.channel_type() |> to_string()

      {:ok,
       new(%{
         provider: provider,
         account_id: client.id,
         external_id: external_id,
         room_id: room_id,
         metadata: %{"signal_type" => type}
       })}
    else
      {:error, :identity_source_missing}
    end
  rescue
    _ -> {:error, :identity_source_invalid}
  end
end
