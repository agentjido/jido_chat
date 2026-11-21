defmodule Jido.Chat.Slack.Renderer do
  @moduledoc """
  Translates canonical cards, modals, and dynamic options to Slack Block Kit.

  Slack provider limits are enforced here. Features that Slack cannot render,
  such as charts, use the canonical accessible text fallback.
  """

  alias Jido.Chat.{Card, Modal}
  alias Jido.Chat.Card.Component
  alias Jido.Chat.Modal.Element

  @message_block_limit 50
  @modal_block_limit 100
  @table_column_limit 20
  @table_row_limit 200
  @table_character_limit 20_000
  @table_page_size_limit 100
  @option_limit 100
  @action_id_limit 255
  @section_text_limit 3_000
  @input_placeholder_limit 150
  @option_label_limit 75
  @option_value_limit 150

  @typedoc "A rendered Slack message body and its fallback status."
  @type card_render :: %{blocks: [map()], text: String.t(), fallback_used: boolean()}

  @doc "Returns Slack's maximum dynamic option or option-group count."
  @spec option_limit() :: pos_integer()
  def option_limit, do: @option_limit

  @doc "Renders a canonical card as Slack message blocks."
  @spec card(Card.t() | map()) :: {:ok, card_render()} | {:error, term()}
  def card(card) do
    card = Card.normalize(card)

    with {:ok, component_blocks, fallback_used} <- render_components(card.components),
         blocks <- card_header_blocks(card) ++ component_blocks,
         :ok <- validate_table_characters(blocks),
         :ok <- validate_message_blocks(blocks),
         :ok <- within_limit(blocks, @message_block_limit, :message_blocks) do
      {:ok,
       %{
         blocks: blocks,
         text: Card.fallback_text(card),
         fallback_used: fallback_used
       }}
    end
  end

  @doc "Renders a canonical modal as a Slack modal view."
  @spec modal(Modal.t() | map()) :: {:ok, map()} | {:error, term()}
  def modal(%{} = payload) when not is_struct(payload) do
    if provider_modal?(payload) do
      {:ok, payload}
    else
      payload |> Modal.new() |> modal()
    end
  end

  def modal(%Modal{} = modal) do
    with :ok <- text_limit(modal.title, 24, :modal_title),
         :ok <- text_limit(modal.submit_label, 24, :modal_submit_label),
         :ok <- text_limit(modal.close_label, 24, :modal_close_label),
         {:ok, blocks} <- render_modal_elements(modal.elements),
         :ok <- within_limit(blocks, @modal_block_limit, :modal_blocks) do
      {:ok,
       %{
         "type" => "modal",
         "callback_id" => modal.callback_id,
         "private_metadata" => modal.private_metadata,
         "notify_on_close" => modal.notify_on_close,
         "title" => plain_text(modal.title),
         "submit" => plain_text(modal.submit_label),
         "close" => plain_text(modal.close_label),
         "blocks" => blocks
       }
       |> compact()}
    end
  end

  @doc "Renders normalized dynamic options as a Slack options-load response."
  @spec options_response(map()) :: {:ok, map()} | {:error, term()}
  def options_response(result) when is_map(result) do
    options = result[:options] || result["options"] || []
    option_groups = result[:option_groups] || result["option_groups"] || []

    cond do
      options != [] and option_groups != [] ->
        {:error, {:provider_validation, :options_and_groups_are_mutually_exclusive}}

      length(options) > @option_limit ->
        provider_limit(:options, @option_limit)

      length(option_groups) > @option_limit ->
        provider_limit(:option_groups, @option_limit)

      true ->
        with {:ok, options} <- render_load_options(options),
             {:ok, groups} <- render_load_groups(option_groups) do
          response =
            %{}
            |> maybe_put("options", options, options != [])
            |> maybe_put("option_groups", groups, groups != [])
            |> maybe_put("options", [], options == [] and groups == [])

          {:ok, response}
        end
    end
  end

  def options_response(_), do: {:error, {:provider_validation, :options}}

  defp card_header_blocks(card) do
    []
    |> maybe_append(card.title && %{"type" => "header", "text" => plain_text(card.title)})
    |> maybe_append(section(card.summary))
    |> maybe_append(section(markdown_text(card.markdown)))
  end

  defp render_components(components) do
    Enum.reduce_while(components, {:ok, [], false}, fn component, {:ok, blocks, fallback?} ->
      case render_component(component) do
        {:ok, rendered, component_fallback?} ->
          {:cont, {:ok, Enum.reverse(rendered, blocks), fallback? or component_fallback?}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed, fallback?} -> {:ok, Enum.reverse(reversed), fallback?}
      error -> error
    end
  end

  defp render_component(%Component{kind: :text} = component),
    do: ok_blocks([section(markdown_text(component.markdown) || component.text)])

  defp render_component(%Component{kind: :section} = component) do
    base =
      []
      |> maybe_append(section(component.title && "*#{component.title}*"))
      |> maybe_append(section(markdown_text(component.markdown) || component.text))

    with {:ok, child_blocks, fallback?} <- render_components(component.items) do
      {:ok, base ++ child_blocks, fallback?}
    end
  end

  defp render_component(%Component{kind: :field} = component) do
    text = "*#{component.label || component.title || "Field"}*\n#{component.text || component.value || ""}"
    ok_blocks([section(text)])
  end

  defp render_component(%Component{kind: :fields} = component) do
    fields =
      Enum.map(component.items, fn item ->
        %{
          "type" => "mrkdwn",
          "text" => "*#{item.label || item.title || "Field"}*\n#{item.text || item.value || ""}"
        }
      end)

    ok_blocks([
      %{"type" => "section", "text" => mrkdwn(component.title || "Details"), "fields" => fields}
    ])
  end

  defp render_component(%Component{kind: kind} = component)
       when kind in [:button, :link_button] do
    with {:ok, element} <- render_action_element(component) do
      ok_blocks([%{"type" => "actions", "elements" => [element]}])
    end
  end

  defp render_component(%Component{kind: :link} = component) do
    label = component.label || component.url || "Link"
    ok_blocks([section("<#{component.url}|#{label}>")])
  end

  defp render_component(%Component{kind: :actions} = component) do
    with {:ok, elements} <- map_ok(component.items, &render_action_element/1),
         :ok <- within_limit(elements, 25, :action_elements) do
      blocks =
        []
        |> maybe_append(section(component.title && "*#{component.title}*"))
        |> Kernel.++([%{"type" => "actions", "elements" => elements}])

      ok_blocks(blocks)
    end
  end

  defp render_component(%Component{kind: kind} = component)
       when kind in [:select, :radio_select, :external_select] do
    with {:ok, element} <- render_action_element(component) do
      ok_blocks([%{"type" => "actions", "elements" => [element]}])
    end
  end

  defp render_component(%Component{kind: :table} = component) do
    with :ok <- validate_table(component) do
      rows = [component.columns | component.rows]

      block =
        %{
          "type" => "data_table",
          "caption" => component.caption || component.title || "Table",
          "rows" => Enum.map(rows, &Enum.map(&1, fn value -> table_cell(value) end)),
          "page_size" => component.page_size
        }
        |> compact()

      ok_blocks([block])
    end
  end

  defp render_component(%Component{kind: kind} = component)
       when kind in [:pie_chart, :bar_chart, :area_chart, :line_chart] do
    ok_blocks([section(chart_fallback(component))], true)
  end

  defp render_component(%Component{kind: :image} = component) do
    {:ok,
     [
       %{
         "type" => "image",
         "image_url" => component.image_url,
         "alt_text" => component.alt_text || component.title || "image",
         "title" => component.title && plain_text(component.title)
       }
       |> compact()
     ], false}
  end

  defp render_component(%Component{kind: :divider}),
    do: ok_blocks([%{"type" => "divider"}])

  defp render_component(%Component{kind: kind}) when kind in [:select_option, :option_group],
    do: {:error, {:unsupported_component_position, kind}}

  defp render_action_element(%Component{kind: kind} = component)
       when kind in [:button, :link_button] do
    with :ok <- action_id_limit(component.id),
         :ok <- text_limit(component.label || component.title || component.id, 75, :button_label) do
      style = normalize_button_style(component.style)

      {:ok,
       %{
         "type" => "button",
         "action_id" => component.id,
         "text" => plain_text(component.label || component.title || component.id),
         "value" => component.value,
         "url" => component.url,
         "style" => style
       }
       |> compact()}
    end
  end

  defp render_action_element(%Component{kind: :select} = component),
    do: render_static_select(component)

  defp render_action_element(%Component{kind: :radio_select} = component) do
    with :ok <- action_id_limit(component.id),
         {:ok, options} <- render_card_options(component.options) do
      {:ok,
       %{
         "type" => "radio_buttons",
         "action_id" => component.id,
         "options" => options,
         "initial_option" => initial_option(options, component.value)
       }
       |> compact()}
    end
  end

  defp render_action_element(%Component{kind: :external_select} = component) do
    placeholder = component.label || component.title || "Select an option"

    with :ok <- action_id_limit(component.id),
         :ok <- input_placeholder_limit(placeholder),
         :ok <- min_query_length_limit(component.min_query_length) do
      {:ok,
       %{
         "type" => "external_select",
         "action_id" => component.id,
         "placeholder" => plain_text(placeholder),
         "min_query_length" => component.min_query_length
       }
       |> compact()}
    end
  end

  defp render_action_element(%Component{kind: kind}),
    do: {:error, {:unsupported_action_component, kind}}

  defp render_static_select(component) do
    placeholder = component.label || component.title || "Select an option"

    with :ok <- action_id_limit(component.id),
         :ok <- input_placeholder_limit(placeholder),
         {:ok, options} <- render_card_options(component.options) do
      {:ok,
       %{
         "type" => "static_select",
         "action_id" => component.id,
         "placeholder" => plain_text(placeholder),
         "options" => options,
         "initial_option" => initial_option(options, component.value)
       }
       |> compact()}
    end
  end

  defp render_card_options(options) do
    if length(options) > @option_limit do
      provider_limit(:options, @option_limit)
    else
      map_ok(options, fn option ->
        render_option(option.label || option.text || option.value, option.value || option.id)
      end)
    end
  end

  defp render_modal_elements(elements), do: map_ok(elements, &render_modal_element/1)

  defp render_modal_element(%Element{kind: :text_input} = element) do
    with :ok <- input_placeholder_limit(element.placeholder) do
      input =
        %{
          "type" => "plain_text_input",
          "action_id" => element.id,
          "initial_value" => element.value,
          "multiline" => element.multiline,
          "min_length" => element.min_length,
          "max_length" => element.max_length,
          "placeholder" => element.placeholder && plain_text(element.placeholder)
        }
        |> compact()

      input_block(element, input)
    end
  end

  defp render_modal_element(%Element{kind: :date_input} = element) do
    cond do
      element.min_date != nil ->
        {:error, {:unsupported_constraint, :date_input, :min_date}}

      element.max_date != nil ->
        {:error, {:unsupported_constraint, :date_input, :max_date}}

      true ->
        with :ok <- input_placeholder_limit(element.placeholder) do
          input =
            %{
              "type" => "datepicker",
              "action_id" => element.id,
              "initial_date" => element.value,
              "placeholder" => element.placeholder && plain_text(element.placeholder)
            }
            |> compact()

          input_block(element, input)
        end
    end
  end

  defp render_modal_element(%Element{kind: :number_input, step: step}) when not is_nil(step),
    do: {:error, {:unsupported_constraint, :number_input, :step}}

  defp render_modal_element(%Element{kind: :number_input} = element) do
    with :ok <- input_placeholder_limit(element.placeholder) do
      input =
        %{
          "type" => "number_input",
          "action_id" => element.id,
          "is_decimal_allowed" => true,
          "initial_value" => element.value,
          "min_value" => stringify_number(element.min_value),
          "max_value" => stringify_number(element.max_value),
          "placeholder" => element.placeholder && plain_text(element.placeholder)
        }
        |> compact()

      input_block(element, input)
    end
  end

  defp render_modal_element(%Element{kind: :select} = element) do
    with :ok <- input_placeholder_limit(element.placeholder),
         {:ok, options} <- render_modal_options(element.options) do
      input =
        %{
          "type" => "static_select",
          "action_id" => element.id,
          "placeholder" => plain_text(element.placeholder || "Select an option"),
          "options" => options,
          "initial_option" => initial_option(options, element.value)
        }
        |> compact()

      input_block(element, input)
    end
  end

  defp render_modal_element(%Element{kind: :radio_select} = element) do
    with {:ok, options} <- render_modal_options(element.options) do
      input =
        %{
          "type" => "radio_buttons",
          "action_id" => element.id,
          "options" => options,
          "initial_option" => initial_option(options, element.value)
        }
        |> compact()

      input_block(element, input)
    end
  end

  defp render_modal_element(%Element{kind: :external_select} = element) do
    with :ok <- input_placeholder_limit(element.placeholder),
         :ok <- min_query_length_limit(element.min_query_length) do
      input =
        %{
          "type" => "external_select",
          "action_id" => element.id,
          "placeholder" => plain_text(element.placeholder || "Select an option"),
          "min_query_length" => element.min_query_length,
          "initial_option" => modal_external_initial_option(element)
        }
        |> compact()

      input_block(element, input)
    end
  end

  defp render_modal_element(%Element{kind: kind}),
    do: {:error, {:unsupported_modal_element_position, kind}}

  defp input_block(element, input) do
    with :ok <- action_id_limit(element.id),
         :ok <- text_limit(element.label || element.id, 2_000, :input_label),
         :ok <- text_limit(element.help_text, 2_000, :input_hint) do
      {:ok,
       %{
         "type" => "input",
         "block_id" => element.id,
         "label" => plain_text(element.label || element.id),
         "optional" => not element.required,
         "hint" => element.help_text && plain_text(element.help_text),
         "element" => input
       }
       |> compact()}
    end
  end

  defp render_modal_options(options) do
    if length(options) > @option_limit do
      provider_limit(:options, @option_limit)
    else
      map_ok(options, &render_option(&1.label || &1.value, &1.value || &1.id))
    end
  end

  defp modal_external_initial_option(%Element{value: nil}), do: nil

  defp modal_external_initial_option(%Element{} = element) do
    options = element.options ++ Enum.flat_map(element.option_groups, & &1.options)

    case Enum.find(options, &((&1.value || &1.id) == element.value)) do
      nil -> nil
      option -> render_option!(option.label || option.value, option.value || option.id)
    end
  end

  defp render_load_options(options),
    do: map_ok(options, &render_option(value(&1, :label), value(&1, :value), value(&1, :description)))

  defp render_load_groups(groups) do
    map_ok(groups, fn group ->
      options = value(group, :options) || []

      if length(options) > @option_limit do
        provider_limit(:group_options, @option_limit)
      else
        label = value(group, :label)

        with :ok <- text_limit(label, @option_label_limit, :option_group_label),
             {:ok, options} <- render_load_options(options) do
          {:ok, %{"label" => plain_text(label), "options" => options}}
        end
      end
    end)
  end

  defp render_option(label, value, description \\ nil) do
    with :ok <- text_limit(label, @option_label_limit, :option_label),
         :ok <- text_limit(value, @option_value_limit, :option_value),
         :ok <- text_limit(description, @option_label_limit, :option_description) do
      {:ok,
       %{
         "text" => plain_text(label),
         "value" => value,
         "description" => description && plain_text(description)
       }
       |> compact()}
    end
  end

  defp render_option!(label, value) do
    {:ok, option} = render_option(label, value)
    option
  end

  defp initial_option(options, value), do: Enum.find(options, &(&1["value"] == value))

  defp validate_table(component) do
    cond do
      length(component.columns) > @table_column_limit ->
        provider_limit(:table_columns, @table_column_limit)

      length(component.rows) > @table_row_limit ->
        provider_limit(:table_rows, @table_row_limit)

      component.page_size != nil and component.page_size > @table_page_size_limit ->
        provider_limit(:table_page_size, @table_page_size_limit)

      true ->
        :ok
    end
  end

  defp validate_table_characters(blocks) do
    total_characters =
      Enum.reduce(blocks, 0, fn
        %{"type" => "data_table", "rows" => rows}, total ->
          Enum.reduce(rows, total, fn row, row_total ->
            Enum.reduce(row, row_total, &(table_cell_characters(&1) + &2))
          end)

        _block, total ->
          total
      end)

    if total_characters > @table_character_limit,
      do: provider_limit(:table_characters, @table_character_limit),
      else: :ok
  end

  defp chart_fallback(component) do
    component.fallback_text || component.alt_text ||
      [component.title, component.caption, chart_label(component.kind), chart_data(component)]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n")
  end

  defp chart_data(%Component{series: [_ | _]} = component) do
    Enum.map_join(component.series, "; ", fn series ->
      values =
        component.categories
        |> Enum.zip(series.values)
        |> Enum.map_join(", ", fn {category, value} -> "#{category}: #{value}" end)

      "#{series.name} — #{values}"
    end)
  end

  defp chart_data(component) do
    Enum.map_join(component.data, "; ", fn point ->
      prefix = if point.series, do: "#{point.series} — ", else: ""
      "#{prefix}#{point.label}: #{point.value}"
    end)
  end

  defp chart_label(:pie_chart), do: "Pie chart"
  defp chart_label(:bar_chart), do: "Bar chart"
  defp chart_label(:area_chart), do: "Area chart"
  defp chart_label(:line_chart), do: "Line chart"

  defp table_cell(value) when is_number(value), do: %{"type" => "raw_number", "value" => value}
  defp table_cell(value), do: %{"type" => "raw_text", "text" => to_string(value)}

  defp table_cell_characters(%{"text" => value}), do: String.length(to_string(value))
  defp table_cell_characters(%{"value" => value}), do: String.length(to_string(value))

  defp stringify_number(nil), do: nil
  defp stringify_number(value), do: to_string(value)

  defp normalize_button_style(style) when style in ["primary", "danger"], do: style
  defp normalize_button_style(:primary), do: "primary"
  defp normalize_button_style(:danger), do: "danger"
  defp normalize_button_style(_style), do: nil

  defp min_query_length_limit(nil), do: :ok

  defp min_query_length_limit(length) when is_integer(length) and length >= 0, do: :ok
  defp min_query_length_limit(_length), do: {:error, {:provider_validation, :min_query_length}}

  defp action_id_limit(value), do: text_limit(value, @action_id_limit, :action_id)

  defp input_placeholder_limit(value),
    do: text_limit(value, @input_placeholder_limit, :input_placeholder)

  defp text_limit(nil, _limit, _field), do: :ok

  defp text_limit(value, limit, field) when is_binary(value) do
    if String.length(value) <= limit, do: :ok, else: provider_limit(field, limit)
  end

  defp text_limit(_value, _limit, field), do: {:error, {:provider_validation, field}}

  defp within_limit(items, limit, field) do
    if length(items) <= limit, do: :ok, else: provider_limit(field, limit)
  end

  defp provider_limit(field, limit), do: {:error, {:provider_limit, field, limit}}

  defp validate_message_blocks(blocks) do
    Enum.reduce_while(blocks, :ok, fn block, :ok ->
      result =
        case block do
          %{"type" => "header", "text" => %{"text" => text}} ->
            text_limit(text, 150, :header_text)

          %{"type" => "section", "text" => %{"text" => text}} ->
            text_limit(text, @section_text_limit, :section_text)

          _other ->
            :ok
        end

      case result do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp section(nil), do: nil
  defp section(""), do: nil

  defp section(text), do: %{"type" => "section", "text" => mrkdwn(text)}

  defp plain_text(text), do: %{"type" => "plain_text", "text" => text, "emoji" => true}
  defp mrkdwn(text), do: %{"type" => "mrkdwn", "text" => text}

  defp markdown_text(nil), do: nil
  defp markdown_text(value) when is_binary(value), do: value
  defp markdown_text(value), do: Jido.Chat.Adapter.render_markdown(value)

  defp ok_blocks(blocks, fallback? \\ false),
    do: {:ok, Enum.reject(blocks, &is_nil/1), fallback?}

  defp map_ok(items, mapper) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case mapper.(item) do
        {:ok, rendered} -> {:cont, {:ok, [rendered | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp provider_modal?(payload) do
    (payload[:type] || payload["type"]) in [:modal, "modal"]
  end

  defp value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp maybe_append(list, nil), do: list
  defp maybe_append(list, value), do: list ++ [value]

  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)
  defp maybe_put(map, _key, _value, false), do: map
end
