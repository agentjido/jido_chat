defmodule Jido.Chat.Handlers.Families do
  @moduledoc false
  use Jido.Signal.Router
  @before_compile Jido.Chat.Handlers.RouterBoundary
  route(Jido.Chat.Signal.MessageReceived, :message)
  route(Jido.Chat.Signal.MessageUpdated, :fact)
  route(Jido.Chat.Signal.MessageDeleted, :fact)
  route(Jido.Chat.Signal.ReactionAdded, :fact)
  route(Jido.Chat.Signal.ReactionRemoved, :fact)
  route(Jido.Chat.Signal.ActionReceived, :fact)
  route(Jido.Chat.Signal.ModalSubmitted, :fact)
  route(Jido.Chat.Signal.ModalClosed, :fact)
  route(Jido.Chat.Signal.OptionsRequested, :fact)
  route(Jido.Chat.Signal.SlashCommandReceived, :fact)
  route(Jido.Chat.Signal.AssistantThreadStarted, :fact)
  route(Jido.Chat.Signal.AssistantContextChanged, :fact)
  route(Jido.Chat.Signal.MembershipChanged, :membership)
  route(Jido.Chat.Signal.ThreadStarted, :fact)
  route(Jido.Chat.Signal.ThreadChanged, :fact)
  route(Jido.Chat.Signal.ReceiptReceived, :fact)
  route(Jido.Chat.Signal.NormalizationFailed, :fact)
end
