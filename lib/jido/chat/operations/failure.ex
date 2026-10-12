defmodule Jido.Chat.Operations.Failure do
  @moduledoc false

  alias Jido.Chat.Binding

  @type class :: :recoverable | :degraded | :fatal
  @terminal_tags [:queue_full, :load_shed, :send_failed, :missing_external_message_id, :invalid_request]

  @doc false
  @spec classify(term()) :: class()
  def classify(%{class: class}) when class in [:recoverable, :degraded, :fatal], do: class
  def classify(%{reason: reason}), do: classify(reason)
  def classify(reason) when reason in [:timeout, :econnrefused, :closed, :nxdomain, :network_error], do: :recoverable

  def classify({kind, _}) when kind in [:timeout, :network_error, :task_exit, :exception, :rate_limited],
    do: :recoverable

  def classify({:api_error, reason}) when reason in [:timeout, :closed], do: :recoverable

  def classify({kind, status}) when kind in [:http_error, :http_status] and is_integer(status) and status >= 500,
    do: :recoverable

  def classify(:unsupported), do: :degraded
  def classify({kind, _}) when kind in [:unsupported, :unsupported_method, :media_policy_denied], do: :degraded
  def classify({:policy_denied, _, _, _}), do: :degraded
  def classify(_), do: :fatal

  @doc false
  @spec tag(term()) :: atom() | nil
  def tag(reason) when reason in @terminal_tags, do: reason
  def tag({reason, _}) when reason in @terminal_tags, do: reason
  def tag(_), do: nil

  @doc false
  @spec remember(Binding.t(), Jido.Signal.t(), class(), atom() | nil) :: :ok
  def remember(binding, result, class, tag) do
    :ets.insert(binding.resources, {{:failure_class, result.id}, class, tag})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc false
  @spec class(Binding.t(), Jido.Signal.t()) :: class()
  def class(binding, result) do
    case :ets.lookup(binding.resources, {:failure_class, result.id}) do
      [{_key, class, _tag}] -> class
      [] -> default_class(result)
    end
  rescue
    ArgumentError -> default_class(result)
  end

  @doc false
  @spec reason_tag(Binding.t(), Jido.Signal.t()) :: atom() | nil
  def reason_tag(binding, result) do
    case :ets.lookup(binding.resources, {:failure_class, result.id}) do
      [{_key, _class, tag}] -> tag
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp default_class(%{data: %{"retryable" => true}}), do: :recoverable
  defp default_class(%{data: %{"code" => "unsupported"}}), do: :degraded
  defp default_class(_), do: :fatal
end
