defmodule Jido.Chat.Emoji do
  @moduledoc """
  Cross-platform emoji helper with a small default registry and custom overrides.
  """

  @defaults %{
    thumbs_up: "👍",
    thumbsup: "👍",
    white_check_mark: "✅",
    check: "✅",
    x: "❌",
    warning: "⚠️",
    eyes: "👀",
    rocket: "🚀",
    tada: "🎉",
    hourglass: "⏳"
  }

  @type registry :: %{optional(atom()) => String.t()}

  @doc "Returns the built-in emoji registry."
  @spec registry() :: registry()
  def registry, do: @defaults

  @doc "Adds or overrides a custom emoji entry in a registry."
  @spec put_custom(registry(), atom() | String.t(), String.t()) :: registry()
  def put_custom(custom, name, rendered) when is_binary(rendered) do
    Map.put(custom || %{}, normalize_name(name), rendered)
  end

  @doc "Renders an emoji token using built-ins plus optional custom overrides."
  @spec render(String.t() | atom(), keyword()) :: String.t()
  def render(value, opts \\ [])

  def render(value, opts) when is_binary(value) do
    if value != "" and not named_emoji?(value) do
      value
    else
      lookup_emoji(value, opts)
    end
  end

  def render(value, opts) do
    lookup_emoji(value, opts)
  end

  defp lookup_emoji(value, opts) do
    custom =
      opts[:custom]
      |> normalize_custom()

    name = normalize_name(value)
    Map.get(custom, name) || Map.get(@defaults, name) || fallback_token(value)
  end

  defp normalize_custom(nil), do: %{}

  defp normalize_custom(custom) when is_map(custom) do
    custom
    |> Enum.map(fn {key, value} -> {normalize_name(key), value} end)
    |> Map.new()
  end

  defp normalize_name(value) when is_atom(value), do: value

  defp normalize_name(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.trim_leading(":")
    |> String.trim_trailing(":")
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  defp fallback_token(value) when is_binary(value), do: value
  defp fallback_token(value) when is_atom(value), do: ":" <> Atom.to_string(value) <> ":"

  defp named_emoji?(value) when is_binary(value) do
    String.starts_with?(value, ":") and String.ends_with?(value, ":")
  end
end
