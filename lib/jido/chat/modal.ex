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

  @doc "Builds a date input element."
  @spec date_input(String.t(), String.t(), keyword() | map()) :: Element.t()
  def date_input(id, label, opts \\ []) when is_binary(id) and is_binary(label) do
    opts = normalize_opts(opts)

    Element.new(%{
      kind: :date_input,
      id: id,
      label: label,
      value: option(opts, :value),
      placeholder: opts[:placeholder] || opts["placeholder"],
      help_text: opts[:help_text] || opts["help_text"],
      fallback_text: opts[:fallback_text] || opts["fallback_text"],
      required: opts[:required] || opts["required"] || false,
      min_date: option(opts, :min_date),
      max_date: option(opts, :max_date),
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds a number input element."
  @spec number_input(String.t(), String.t(), keyword() | map()) :: Element.t()
  def number_input(id, label, opts \\ []) when is_binary(id) and is_binary(label) do
    opts = normalize_opts(opts)

    Element.new(%{
      kind: :number_input,
      id: id,
      label: label,
      value: option(opts, :value),
      placeholder: opts[:placeholder] || opts["placeholder"],
      help_text: opts[:help_text] || opts["help_text"],
      fallback_text: opts[:fallback_text] || opts["fallback_text"],
      required: opts[:required] || opts["required"] || false,
      min_value: option(opts, :min_value),
      max_value: option(opts, :max_value),
      step: option(opts, :step),
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

  @doc "Builds a select option group element."
  @spec select_option_group(String.t(), [Element.t() | map()], keyword() | map()) :: Element.t()
  def select_option_group(label, options, opts \\ [])
      when is_binary(label) and is_list(options) do
    opts = normalize_opts(opts)

    Element.new(%{
      kind: :option_group,
      id: opts[:id] || opts["id"] || label,
      label: label,
      options: options,
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

  @doc "Builds a select whose options load from an external source."
  @spec external_select(String.t(), String.t(), keyword() | map()) :: Element.t()
  def external_select(id, label, opts \\ []) when is_binary(id) and is_binary(label) do
    opts = normalize_opts(opts)

    Element.new(%{
      kind: :external_select,
      id: id,
      label: label,
      value: option(opts, :value),
      placeholder: opts[:placeholder] || opts["placeholder"],
      help_text: opts[:help_text] || opts["help_text"],
      fallback_text: opts[:fallback_text] || opts["fallback_text"],
      required: opts[:required] || opts["required"] || false,
      options: opts[:options] || opts["options"] || [],
      option_groups: opts[:option_groups] || opts["option_groups"] || [],
      options_source: normalize_options_source(opts[:options_source] || opts["options_source"]),
      min_query_length: option(opts, :min_query_length),
      timeout_ms: option(opts, :timeout_ms),
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds a dynamic select. This is an alias for `external_select/3`."
  @spec dynamic_select(String.t(), String.t(), keyword() | map()) :: Element.t()
  def dynamic_select(id, label, opts \\ []) do
    opts = normalize_opts(opts) |> Map.put(:options_source, :dynamic)
    external_select(id, label, opts)
  end

  @doc "Returns deterministic accessible text for a modal."
  @spec fallback_text(t()) :: String.t()
  def fallback_text(%__MODULE__{} = modal) do
    ([modal.title] ++ Enum.map(modal.elements, &element_fallback_text/1))
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  @doc "Returns a plain map suitable for adapter-specific modal rendering."
  @spec to_adapter_payload(t()) :: map()
  def to_adapter_payload(%__MODULE__{} = modal) do
    modal
    |> Map.from_struct()
    |> Map.update!(:elements, fn elements -> Enum.map(elements, &element_to_plain/1) end)
    |> Map.put(:fallback_text, fallback_text(modal))
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
    |> Map.update!(:option_groups, fn groups -> Enum.map(groups, &element_to_plain/1) end)
    |> Wire.to_plain()
  end

  defp element_fallback_text(%Element{fallback_text: text}) when is_binary(text), do: text

  defp element_fallback_text(%Element{kind: :date_input} = element) do
    input_description(element, "date input") <>
      optional_sentence("Minimum date", element.min_date) <>
      optional_sentence("Maximum date", element.max_date) <>
      help_sentence(element.help_text)
  end

  defp element_fallback_text(%Element{kind: :number_input} = element) do
    input_description(element, "number input") <>
      optional_sentence("Minimum", element.min_value) <>
      optional_sentence("Maximum", element.max_value) <>
      optional_sentence("Step", element.step) <>
      help_sentence(element.help_text)
  end

  defp element_fallback_text(%Element{kind: :text_input} = element) do
    input_description(element, if(element.multiline, do: "multiline text input", else: "text input")) <>
      help_sentence(element.help_text)
  end

  defp element_fallback_text(%Element{kind: kind} = element)
       when kind in [:select, :radio_select, :external_select] do
    type =
      case kind do
        :select -> "select input"
        :radio_select -> "radio select input"
        :external_select -> "external select input"
      end

    input_description(element, type) <> help_sentence(element.help_text)
  end

  defp element_fallback_text(%Element{kind: :option_group} = element) do
    labels = Enum.map_join(element.options, ", ", &(&1.label || &1.value))
    "#{element.label}: #{labels}."
  end

  defp element_fallback_text(%Element{kind: :select_option} = element),
    do: element.label || element.value || "Option"

  defp input_description(element, type) do
    requirement = if element.required, do: ", required", else: ""
    "#{element.label || element.id} (#{type}#{requirement})."
  end

  defp optional_sentence(_label, nil), do: ""
  defp optional_sentence(label, value), do: " #{label}: #{format_value(value)}."

  defp help_sentence(nil), do: ""
  defp help_sentence(value), do: " #{value}"

  defp format_value(value) when is_number(value), do: to_string(value)
  defp format_value(value), do: to_string(value)

  defp normalize_options_source(nil), do: :external
  defp normalize_options_source(source) when source in [:external, :dynamic], do: source
  defp normalize_options_source("external"), do: :external
  defp normalize_options_source("dynamic"), do: :dynamic
  defp normalize_options_source(source), do: source

  defp option(opts, key) do
    Map.get(opts, key, Map.get(opts, Atom.to_string(key)))
  end
end
