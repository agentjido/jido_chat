defmodule Jido.Chat.Errors.Validation do
  @moduledoc """
  Schema validation error for named Jido.Chat structs.
  """

  use Splode.Error,
    class: :validation,
    fields: [
      :subject,
      :input,
      errors: []
    ]

  @impl true
  def message(%__MODULE__{subject: subject, errors: errors}) do
    base = "invalid #{subject(subject)}"

    case format_errors(errors) do
      "" -> base
      detail -> "#{base}: #{detail}"
    end
  end

  defp subject(nil), do: "data"
  defp subject(value) when is_atom(value), do: inspect(value)
  defp subject(value), do: to_string(value)

  defp format_errors(errors) when is_list(errors) do
    errors
    |> Enum.map_join("; ", &format_error/1)
  end

  defp format_errors(_), do: ""

  defp format_error(%Zoi.Error{message: message, path: path}) do
    case format_path(path) do
      "" -> message
      path -> "#{path} #{message}"
    end
  end

  defp format_error(%{message: message}) when is_binary(message), do: message
  defp format_error(other), do: inspect(other)

  defp format_path(path) when is_list(path) and path != [] do
    Enum.map_join(path, ".", &to_string/1) <> ":"
  end

  defp format_path(_), do: ""
end
