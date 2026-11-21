defmodule Jido.Chat.Telegram do
  @moduledoc """
  Telegram adapter for `Jido.Chat`.

  Use core Chat Actions with this adapter. Telegram-specific Actions use the
  same Client, Signal, Flow, and Router contracts. The host owns all runtime
  processes, update offsets, draft timing, and retries.
  """

  alias Jido.Chat.Telegram.Adapter

  @doc "Returns the canonical Telegram adapter module."
  @spec adapter() :: module()
  def adapter, do: Adapter

  @doc "Returns the native Telegram extension Actions. Core Actions are in Jido.Chat.actions/0."
  @spec actions() :: [module()]
  def actions do
    [
      Jido.Chat.Telegram.SendPoll,
      Jido.Chat.Telegram.SendPhoto,
      Jido.Chat.Telegram.SendDocument,
      Jido.Chat.Telegram.SendSticker,
      Jido.Chat.Telegram.SendAnimation,
      Jido.Chat.Telegram.SendVideoNote,
      Jido.Chat.Telegram.GetFile,
      Jido.Chat.Telegram.GetMe,
      Jido.Chat.Telegram.AnswerCallbackQuery,
      Jido.Chat.Telegram.SendDraft,
      Jido.Chat.Telegram.FetchUpdates,
      Jido.Chat.Telegram.SetWebhook,
      Jido.Chat.Telegram.GetWebhookInfo,
      Jido.Chat.Telegram.DeleteWebhook
    ]
  end

  @doc "Returns Telegram extension request/Action pairs. The host owns routing and execution."
  @spec operations() :: [{module(), module()}]
  def operations, do: actions() |> Enum.map(&{&1.signal_definition(), &1}) |> Enum.sort()

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
  def signal_definitions, do: Enum.flat_map(actions(), & &1.signal_definitions())

  @doc "Returns a catalog with core Chat and Telegram extension definitions."
  @spec catalog() :: Jido.Signal.Catalog.t()
  def catalog, do: Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions() ++ signal_definitions())
end
