defmodule Jido.Chat.Slack do
  @moduledoc """
  Slack adapter for `Jido.Chat`.

  This package uses Slack's Web API. The host can use the Socket Mode Source or
  pure webhook helpers for ingress.
  """

  alias Jido.Chat.Slack.{Adapter, Source, Webhook}

  @doc "Returns the canonical Slack adapter module."
  @spec adapter() :: module()
  def adapter, do: Adapter

  @doc "Returns the Slack Socket Mode source module."
  @spec source() :: module()
  def source, do: Source

  @doc "Returns the Slack webhook helper module."
  @spec webhook() :: module()
  def webhook, do: Webhook

  @doc "Returns provider extension request and Action pairs."
  @spec operations() :: []
  def operations, do: []

  @doc "Returns the incoming facts normalized by Slack."
  @spec event_definitions() :: [module()]
  def event_definitions do
    [
      Jido.Chat.Signal.MessageReceived,
      Jido.Chat.Signal.MessageUpdated,
      Jido.Chat.Signal.MessageDeleted,
      Jido.Chat.Signal.ReactionAdded,
      Jido.Chat.Signal.ReactionRemoved,
      Jido.Chat.Signal.ActionReceived,
      Jido.Chat.Signal.ModalSubmitted,
      Jido.Chat.Signal.ModalClosed,
      Jido.Chat.Signal.OptionsRequested,
      Jido.Chat.Signal.SlashCommandReceived,
      Jido.Chat.Signal.NormalizationFailed
    ]
  end
end
