defmodule Jido.Chat.Authentication.Request do
  @moduledoc """
  Private synchronous onboarding requests to the configured host sink.

  `:persist` saves the confirmed account and credentials; `:start` activates the
  saved connector after volatile state has been seeded. These remain separate
  operations so activation failure cannot discard a committed receipt.

  The session bounds execution to ten seconds and its remaining lifetime. Hosts
  must authorize the supplied context, commit before acknowledging persistence,
  and make persistence idempotent by attempt ID. Requests must never enter public
  webhook, chat action, or serialized listener State routing.
  """

  @derive {Inspect, only: [:version, :id]}
  @enforce_keys [:context, :request]
  defstruct [:context, :request, version: 1, id: nil]

  @type t :: %__MODULE__{context: term(), request: map(), version: 1, id: reference() | nil}

  @doc "Dispatches a private request inside the pairing session's bounded task."
  @spec call(tuple(), term(), map()) :: term()
  def call({module, function, args}, context, %{op: op} = request)
      when is_atom(module) and is_atom(function) and is_list(args) and op in [:persist, :start] do
    event = %__MODULE__{context: context, request: request, id: make_ref()}

    case apply(module, function, args ++ [event, []]) do
      :ok -> :ok
      {:ok, _} = result -> result
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :callback_failed}
    end
  rescue
    _ -> {:error, :callback_failed}
  catch
    _, _ -> {:error, :callback_failed}
  end

  def call(_, _, _), do: {:error, :invalid_pairing_request}
end
