defmodule Jido.Chat.Card do
  @moduledoc """
  Canonical cross-platform card model with fallback rendering helpers.
  """

  alias Jido.Chat.Card.Component
  alias Jido.Chat.Markdown
  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string() |> Zoi.nullish(),
              title: Zoi.string() |> Zoi.nullish(),
              summary: Zoi.string() |> Zoi.nullish(),
              markdown: Zoi.any() |> Zoi.nullish(),
              components: Zoi.list() |> Zoi.default([]),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @type component :: Component.t()

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for cards."
  def schema, do: @schema

  @doc "Creates a canonical card."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = card), do: card

  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_markdown()
    |> normalize_components()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Normalizes card input."
  @spec normalize(t() | map()) :: t()
  def normalize(%__MODULE__{} = card), do: card
  def normalize(map) when is_map(map), do: new(map)

  @doc "Adds a component to the end of a card."
  @spec add(t(), component() | map() | String.t()) :: t()
  def add(%__MODULE__{} = card, component) do
    %{card | components: card.components ++ [Component.normalize(component)]}
  end

  @doc "Builds a text component."
  @spec text(String.t(), keyword() | map()) :: component()
  def text(value, opts \\ []) when is_binary(value) do
    opts = normalize_opts(opts)
    Component.new(%{kind: :text, text: value, markdown: opts[:markdown] || opts["markdown"]})
  end

  @doc "Builds a section component."
  @spec section(keyword() | map()) :: component()
  def section(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = normalize_opts(attrs)

    Component.new(%{
      kind: :section,
      title: attrs[:title] || attrs["title"],
      text: attrs[:text] || attrs["text"],
      markdown: attrs[:markdown] || attrs["markdown"],
      items: attrs[:items] || attrs["items"] || []
    })
  end

  @doc "Builds a field component."
  @spec field(String.t(), String.t(), keyword() | map()) :: component()
  def field(label, value, opts \\ []) when is_binary(label) do
    opts = normalize_opts(opts)
    Component.new(%{kind: :field, label: label, text: value, metadata: opts[:metadata] || %{}})
  end

  @doc "Builds a grouped fields component."
  @spec fields([component() | map()], keyword() | map()) :: component()
  def fields(items, opts \\ []) when is_list(items) do
    opts = normalize_opts(opts)
    Component.new(%{kind: :fields, title: opts[:title], items: items})
  end

  @doc "Builds a button component."
  @spec button(String.t(), String.t(), keyword() | map()) :: component()
  def button(label, action_id, opts \\ []) when is_binary(label) and is_binary(action_id) do
    opts = normalize_opts(opts)

    Component.new(%{
      kind: :button,
      id: action_id,
      label: label,
      value: opts[:value] || opts["value"],
      style: opts[:style] || opts["style"],
      disabled: opts[:disabled] || opts["disabled"] || false,
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds a link button component."
  @spec link_button(String.t(), String.t(), keyword() | map()) :: component()
  def link_button(label, url, opts \\ []) when is_binary(label) and is_binary(url) do
    opts = normalize_opts(opts)

    Component.new(%{
      kind: :link_button,
      label: label,
      url: url,
      style: opts[:style] || opts["style"],
      disabled: opts[:disabled] || opts["disabled"] || false,
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds a text link component."
  @spec link(String.t(), String.t(), keyword() | map()) :: component()
  def link(label, url, opts \\ []) when is_binary(label) and is_binary(url) do
    opts = normalize_opts(opts)
    Component.new(%{kind: :link, label: label, url: url, metadata: opts[:metadata] || %{}})
  end

  @doc "Builds an actions component."
  @spec actions([component() | map()], keyword() | map()) :: component()
  def actions(items, opts \\ []) when is_list(items) do
    opts = normalize_opts(opts)
    Component.new(%{kind: :actions, title: opts[:title], items: items})
  end

  @doc "Builds a select option component."
  @spec select_option(String.t(), String.t(), keyword() | map()) :: component()
  def select_option(label, value, opts \\ []) when is_binary(label) and is_binary(value) do
    opts = normalize_opts(opts)

    Component.new(%{
      kind: :select_option,
      label: label,
      value: value,
      text: opts[:text] || opts["text"],
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds a select component."
  @spec select(String.t(), [component() | map()], keyword() | map()) :: component()
  def select(action_id, options, opts \\ []) when is_binary(action_id) and is_list(options) do
    opts = normalize_opts(opts)

    Component.new(%{
      kind: :select,
      id: action_id,
      label: opts[:label] || opts["label"],
      title: opts[:title] || opts["title"],
      value: opts[:value] || opts["value"],
      options: options,
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds a radio select component."
  @spec radio_select(String.t(), [component() | map()], keyword() | map()) :: component()
  def radio_select(action_id, options, opts \\ [])
      when is_binary(action_id) and is_list(options) do
    opts = normalize_opts(opts)

    Component.new(%{
      kind: :radio_select,
      id: action_id,
      label: opts[:label] || opts["label"],
      title: opts[:title] || opts["title"],
      value: opts[:value] || opts["value"],
      options: options,
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds a table component."
  @spec table([String.t()], [[String.t()]], keyword() | map()) :: component()
  def table(columns, rows, opts \\ []) when is_list(columns) and is_list(rows) do
    opts = normalize_opts(opts)

    Component.new(%{
      kind: :table,
      title: opts[:title] || opts["title"],
      columns: columns,
      rows: rows,
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds an image component."
  @spec image(String.t(), keyword() | map()) :: component()
  def image(url, opts \\ []) when is_binary(url) do
    opts = normalize_opts(opts)

    Component.new(%{
      kind: :image,
      image_url: url,
      alt_text: opts[:alt_text] || opts["alt_text"],
      title: opts[:title] || opts["title"],
      metadata: opts[:metadata] || opts["metadata"] || %{}
    })
  end

  @doc "Builds a divider component."
  @spec divider() :: component()
  def divider, do: Component.new(%{kind: :divider})

  @doc "Renders the card to canonical Markdown."
  @spec to_markdown(t()) :: Markdown.t()
  def to_markdown(%__MODULE__{} = card) do
    children =
      []
      |> maybe_prepend_title(card.title)
      |> maybe_append_summary(card.summary)
      |> maybe_append_markdown(card.markdown)
      |> Kernel.++(Enum.flat_map(card.components, &component_to_markdown/1))

    Markdown.root(children)
  end

  @doc "Returns the best text fallback for a card."
  @spec fallback_text(t()) :: String.t()
  def fallback_text(%__MODULE__{} = card) do
    card
    |> to_markdown()
    |> Markdown.plain_text()
    |> String.trim()
  end

  @doc "Returns a plain map suitable for adapter-specific rendering."
  @spec to_adapter_payload(t()) :: map()
  def to_adapter_payload(%__MODULE__{} = card) do
    card
    |> Map.from_struct()
    |> Map.update!(:components, fn components ->
      Enum.map(components, &component_to_plain/1)
    end)
    |> Map.update!(:markdown, fn
      nil -> nil
      %Markdown{} = markdown -> Markdown.stringify(markdown)
      other -> other
    end)
    |> Wire.to_plain()
  end

  @doc "Serializes a card into a plain map with a type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = card) do
    card
    |> Map.from_struct()
    |> Map.update!(:components, &Enum.map(&1, fn component -> Component.to_map(component) end))
    |> Map.update!(:markdown, fn
      nil -> nil
      %Markdown{} = markdown -> Markdown.to_map(markdown)
      other -> other
    end)
    |> Wire.to_plain()
    |> Map.put("__type__", "card")
  end

  @doc "Builds a card from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()

  defp normalize_markdown(attrs) do
    case attrs[:markdown] || attrs["markdown"] do
      nil ->
        attrs

      %Markdown{} = markdown ->
        Map.put(attrs, :markdown, markdown)

      %{} = markdown ->
        Map.put(attrs, :markdown, Markdown.new(markdown))

      value when is_binary(value) ->
        Map.put(attrs, :markdown, Markdown.parse(value))
    end
  end

  defp normalize_components(attrs) do
    components = attrs[:components] || attrs["components"] || []

    attrs
    |> Map.delete("components")
    |> Map.put(:components, Enum.map(components, &Component.normalize/1))
  end

  defp maybe_prepend_title(children, nil), do: children
  defp maybe_prepend_title(children, title), do: children ++ [Markdown.heading(2, title)]

  defp maybe_append_summary(children, nil), do: children
  defp maybe_append_summary(children, summary), do: children ++ [Markdown.paragraph(summary)]

  defp maybe_append_markdown(children, nil), do: children
  defp maybe_append_markdown(children, %Markdown{root: root}), do: children ++ root.children

  defp component_to_markdown(%Component{} = component) do
    case component.kind do
      :text ->
        component_markdown_or_text(component)

      :section ->
        []
        |> maybe_prepend_component_title(component.title)
        |> maybe_append_component_text(component.text)
        |> maybe_append_component_markdown(component.markdown)
        |> Kernel.++(Enum.flat_map(component.items, &component_to_markdown/1))

      :field ->
        label = component.label || component.title || "Field"
        value = component.text || component.value || ""
        [Markdown.paragraph("#{label}: #{value}")]

      :fields ->
        heading = if component.title, do: [Markdown.heading(3, component.title)], else: []
        heading ++ Enum.flat_map(component.items, &component_to_markdown/1)

      :button ->
        label = component.label || component.title || component.id || "Action"
        [Markdown.list([Markdown.list_item(label)])]

      :link_button ->
        [
          Markdown.list([
            Markdown.list_item(Markdown.link(component.label || "Open", component.url || "#"))
          ])
        ]

      :link ->
        [
          Markdown.paragraph([
            Markdown.link(component.label || component.url || "Link", component.url || "#")
          ])
        ]

      :actions ->
        heading = if component.title, do: [Markdown.heading(3, component.title)], else: []
        heading ++ Enum.flat_map(component.items, &component_to_markdown/1)

      :select ->
        label = component.label || component.title || component.id || "Select"
        options = Enum.map(component.options, &select_option_label/1)
        [Markdown.heading(4, label), Markdown.list(options)]

      :radio_select ->
        label = component.label || component.title || component.id || "Options"
        options = Enum.map(component.options, &select_option_label/1)
        [Markdown.heading(4, label), Markdown.list(options)]

      :table ->
        table_rows = [component.columns | component.rows]
        [Markdown.table(table_rows)]

      :image ->
        label = component.alt_text || component.title || component.image_url || "image"
        [Markdown.paragraph(label)]

      :divider ->
        [Markdown.divider()]

      :select_option ->
        [Markdown.paragraph(select_option_label(component))]
    end
  end

  defp component_markdown_or_text(%Component{markdown: %Markdown{root: root}}), do: root.children

  defp component_markdown_or_text(%Component{text: text}) when is_binary(text),
    do: [Markdown.paragraph(text)]

  defp component_markdown_or_text(_component), do: [Markdown.paragraph("")]

  defp maybe_prepend_component_title(children, nil), do: children

  defp maybe_prepend_component_title(children, title),
    do: children ++ [Markdown.heading(3, title)]

  defp maybe_append_component_text(children, nil), do: children
  defp maybe_append_component_text(children, text), do: children ++ [Markdown.paragraph(text)]

  defp maybe_append_component_markdown(children, nil), do: children

  defp maybe_append_component_markdown(children, %Markdown{root: root}),
    do: children ++ root.children

  defp select_option_label(%Component{} = option),
    do: option.label || option.text || option.value || "option"

  defp component_to_plain(%Component{} = component) do
    component
    |> Map.from_struct()
    |> Map.update!(:items, fn items -> Enum.map(items, &component_to_plain/1) end)
    |> Map.update!(:options, fn options -> Enum.map(options, &component_to_plain/1) end)
    |> Map.update!(:markdown, fn
      nil -> nil
      %Markdown{} = markdown -> Markdown.stringify(markdown)
      other -> other
    end)
    |> Wire.to_plain()
  end

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts
end
