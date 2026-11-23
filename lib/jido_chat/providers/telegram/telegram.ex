defmodule Jido.Chat.Telegram do
  @moduledoc """
  Telegram adapter for `Jido.Chat`.

  Use core Chat Actions with this adapter. Telegram-specific Actions use the
  same Client, Signal, Flow, and Router contracts. The host owns all runtime
  processes, update offsets, draft timing, and retries.
  """

  alias Jido.Chat.Operations.Definition, as: Operation
  alias Jido.Chat.Telegram.Adapter

  @doc "Returns the canonical Telegram adapter module."
  @spec adapter() :: module()
  def adapter, do: Adapter

  @doc "Returns the native Telegram extension Actions. Core Actions are in Jido.Chat.actions/0."
  @spec actions() :: [module()]
  def actions, do: Enum.map(Adapter.operation_definitions(), & &1.action)

  @doc "Returns Telegram extension request/Action pairs. The host owns routing and execution."
  @spec operations() :: [{module(), module()}]
  def operations, do: Enum.map(Adapter.operation_definitions(), &Operation.pair/1) |> Enum.sort()

  @doc "Returns the incoming facts normalized by Telegram."
  @spec event_definitions() :: [module()]
  def event_definitions do
    [
      Jido.Chat.Signal.MessageReceived,
      Jido.Chat.Signal.MessageUpdated,
      Jido.Chat.Signal.ReactionAdded,
      Jido.Chat.Signal.ReactionRemoved,
      Jido.Chat.Signal.ActionReceived,
      Jido.Chat.Signal.MembershipChanged,
      Jido.Chat.Signal.SlashCommandReceived,
      Jido.Chat.Signal.NormalizationFailed,
      Jido.Chat.Signal.ThreadStarted,
      Jido.Chat.Signal.ThreadChanged
    ]
  end

  @doc "Returns Telegram request, completion, and failure definitions for a host catalog."
  @spec signal_definitions() :: [module()]
  def signal_definitions, do: Enum.flat_map(Adapter.operation_definitions(), &Operation.signal_definitions/1)

  @doc "Returns a catalog with core Chat and Telegram extension definitions."
  @spec catalog() :: Jido.Signal.Catalog.t()
  def catalog, do: Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions() ++ signal_definitions())
end
