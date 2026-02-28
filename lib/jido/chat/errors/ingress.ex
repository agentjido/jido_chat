defmodule Jido.Chat.Errors.Ingress do
  @moduledoc """
  Inbound routing error wrapper for request/event transport flows.
  """

  use Splode.Error,
    class: :ingress,
    fields: [
      :transport,
      :adapter_name,
      :reason,
      context: %{}
    ]

  @impl true
  def message(%__MODULE__{transport: transport, adapter_name: adapter_name, reason: reason}) do
    transport_label =
      case transport do
        value when is_atom(value) -> Atom.to_string(value)
        value -> inspect(value)
      end

    adapter_label =
      case adapter_name do
        value when is_atom(value) -> Atom.to_string(value)
        nil -> "unknown"
        value -> to_string(value)
      end

    "ingress #{transport_label} routing failed for adapter #{adapter_label}: #{inspect(reason)}"
  end
end
