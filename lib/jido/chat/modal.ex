defmodule Jido.Chat.Modal do
  @moduledoc """
  Canonical modal open payload and builder helpers.
  """

  alias Jido.Chat.Modal.Element
  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string() |> Zoi.nullish(),
              callback_id: Zoi.string() |> Zoi.nullish(),
              title: Zoi.string(),
              submit_label: Zoi.string() |> Zoi.default("Submit"),
              close_label: Zoi.string() |> Zoi.default("Cancel"),
              notify_on_close: Zoi.boolean() |> Zoi.default(false),
              private_metadata: Zoi.string() |> Zoi.nullish(),
              elements: Zoi.list() |> Zoi.default([]),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for modals."
  def schema, do: @schema

  @doc "Creates a canonical modal."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = modal), do: modal

  def new(attrs) when is_map(attrs) do
    attrs
    |> Map.put_new(
      :callback_id,
      attrs[:id] || attrs["id"] || attrs[:callback_id] || attrs["callback_id"]
    )
    |> normalize_elements()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Builds a text input element."
  @spec text_input(String.t(), String.t(), keyword() | map()) :: Element.t()
  def text_input(id, label, opts \\ []) when is_binary(id) and is_binary(label) do
    opts = normalize_opts(opts)

    Element.new(%{
      kind: :text_input,
      id: id,
      label: label,
      value: opts[:value] || opts["value"],
      placeholder: opts[:placeholder] || opts["placeholder"],
      help_text: opts[:help_text] || opts["help_text"],
      required: opts[:required] || opts["required"] || false,
      multiline: opts[:multiline] || opts["multiline"] || false,
      min_length: opts[:min_length] || opts["min_length"],
      max_length: opts[:max_length] || opts["max_length"],
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds a select option element."
  @spec select_option(String.t(), String.t(), keyword() | map()) :: Element.t()
  def select_option(label, value, opts \\ []) when is_binary(label) and is_binary(value) do
    opts = normalize_opts(opts)

    Element.new(%{
      kind: :select_option,
      id: value,
      label: label,
      value: value,
      help_text: opts[:help_text] || opts["help_text"],
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds a select element."
  @spec select(String.t(), String.t(), [Element.t() | map()], keyword() | map()) :: Element.t()
  def select(id, label, options, opts \\ [])
      when is_binary(id) and is_binary(label) and is_list(options) do
    opts = normalize_opts(opts)

    Element.new(%{
      kind: :select,
      id: id,
      label: label,
      value: opts[:value] || opts["value"],
      placeholder: opts[:placeholder] || opts["placeholder"],
      help_text: opts[:help_text] || opts["help_text"],
      required: opts[:required] || opts["required"] || false,
      options: options,
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds a radio select element."
  @spec radio_select(String.t(), String.t(), [Element.t() | map()], keyword() | map()) ::
          Element.t()
  def radio_select(id, label, options, opts \\ [])
      when is_binary(id) and is_binary(label) and is_list(options) do
    opts = normalize_opts(opts)

    Element.new(%{
      kind: :radio_select,
      id: id,
      label: label,
      value: opts[:value] || opts["value"],
      help_text: opts[:help_text] || opts["help_text"],
      required: opts[:required] || opts["required"] || false,
      options: options,
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Returns a plain map suitable for adapter-specific modal rendering."
  @spec to_adapter_payload(t()) :: map()
  def to_adapter_payload(%__MODULE__{} = modal) do
    modal
    |> Map.from_struct()
    |> Map.update!(:elements, fn elements -> Enum.map(elements, &element_to_plain/1) end)
    |> Wire.to_plain()
  end

  @doc "Serializes the modal into a plain map with a type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = modal) do
    modal
    |> Map.from_struct()
    |> Map.update!(:elements, &Enum.map(&1, fn element -> Element.to_map(element) end))
    |> Wire.to_plain()
    |> Map.put("__type__", "modal")
  end

  @doc "Builds a modal from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()

  defp normalize_elements(attrs) do
    elements = attrs[:elements] || attrs["elements"] || []

    attrs
    |> Map.delete("elements")
    |> Map.put(:elements, Enum.map(elements, &Element.normalize/1))
  end

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts

  defp element_to_plain(%Element{} = element) do
    element
    |> Map.from_struct()
    |> Map.update!(:options, fn options -> Enum.map(options, &element_to_plain/1) end)
    |> Wire.to_plain()
  end
end
