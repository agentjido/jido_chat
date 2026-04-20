defmodule Jido.Chat.ModalResponse do
  @moduledoc """
  Canonical modal lifecycle response used by submit and close handlers.
  """

  alias Jido.Chat.Modal
  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              action: Zoi.enum([:close, :errors, :update, :push]),
              modal: Zoi.any() |> Zoi.nullish(),
              errors: Zoi.map() |> Zoi.default(%{}),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for modal responses."
  def schema, do: @schema

  @doc "Creates a canonical modal response."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = response), do: response

  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_modal()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Builds a close response."
  @spec close(keyword() | map()) :: t()
  def close(opts \\ []), do: new(Map.merge(normalize_opts(opts), %{action: :close}))

  @doc "Builds a validation-error response."
  @spec errors(map(), keyword() | map()) :: t()
  def errors(errors, opts \\ []) when is_map(errors) do
    new(Map.merge(normalize_opts(opts), %{action: :errors, errors: errors}))
  end

  @doc "Builds an update response with a replacement modal."
  @spec update(Modal.t() | map(), keyword() | map()) :: t()
  def update(modal, opts \\ []) do
    new(Map.merge(normalize_opts(opts), %{action: :update, modal: modal}))
  end

  @doc "Builds a push response with a new modal."
  @spec push(Modal.t() | map(), keyword() | map()) :: t()
  def push(modal, opts \\ []) do
    new(Map.merge(normalize_opts(opts), %{action: :push, modal: modal}))
  end

  @doc "Returns a plain adapter-facing response map."
  @spec to_adapter_payload(t()) :: map()
  def to_adapter_payload(%__MODULE__{} = response), do: to_map(response)

  @doc "Serializes the response into a plain map with a type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = response) do
    response
    |> Map.from_struct()
    |> Map.update!(:modal, fn
      nil -> nil
      %Modal{} = modal -> Modal.to_map(modal)
      other -> other
    end)
    |> Wire.to_plain()
    |> Map.put("__type__", "modal_response")
  end

  @doc "Builds a modal response from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()

  defp normalize_modal(attrs) do
    case attrs[:modal] || attrs["modal"] do
      nil ->
        attrs

      %Modal{} = modal ->
        attrs
        |> Map.delete("modal")
        |> Map.put(:modal, modal)

      %{} = modal ->
        attrs
        |> Map.delete("modal")
        |> Map.put(:modal, Modal.new(modal))
    end
  end

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts
end
