defmodule Jido.Chat.Errors do
  @moduledoc """
  Splode error definitions and handler for Jido.Chat.
  """

  defmodule Contract do
    @moduledoc """
    A public Signal contract error.

    `code` identifies the rejected contract condition. `field` is an optional
    field name. The error does not retain provider payloads or private resources.
    """

    use Splode.Error, class: :validation, fields: [:code, :field]

    @typedoc "One rejected public contract condition without private input data."
    @type t :: %__MODULE__{code: atom() | nil, field: atom() | nil}

    @impl true
    def message(%__MODULE__{code: code}), do: "Signal contract rejected: #{code}"
  end

  defmodule Validation do
    @moduledoc """
    Schema validation error for named Jido.Chat structs.
    """

    use Splode.Error,
      class: :validation,
      fields: [
        :subject,
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

  defmodule Unknown do
    @moduledoc false

    use Splode.ErrorClass, class: :unknown
  end

  use Splode,
    error_classes: [
      validation: Validation
    ],
    unknown_error: Unknown
end

defmodule Jido.Chat.Error do
  @moduledoc """
  A provider operation error with a safe failure Signal.

  `signal.data["outcome"]` distinguishes a call that did not start, a rejected
  call, and an unknown outcome. The host owns retry and recovery policy.
  Raw provider errors and credentials are not retained.
  """
  use Splode.Error, class: :unknown, fields: [:code, :signal]
  @type t :: %__MODULE__{code: atom(), signal: Jido.Signal.t()}
  @impl true
  def message(error), do: "Chat operation failed: #{error.code}"
end
