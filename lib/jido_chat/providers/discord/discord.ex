defmodule Jido.Chat.Discord do
  @moduledoc "Discord Client, native Actions, and a host-owned Gateway Source."
  @doc "Return the Discord adapter module."
  @spec adapter() :: module()
  def adapter, do: Jido.Chat.Discord.Adapter

  @doc "Return the native Discord Actions."
  @spec actions() :: [module()]
  def actions,
    do: [Jido.Chat.Discord.RespondInteraction, Jido.Chat.Discord.SendRichMessage, Jido.Chat.Discord.StartMessageThread]

  @doc "Return native request and Action pairs."
  @spec operations() :: [{module(), module()}]
  def operations, do: Enum.map(actions(), &{&1.signal_definition(), &1})
  @doc "Return native request, completion, and failure definitions."
  @spec signal_definitions() :: [module()]
  def signal_definitions, do: Enum.flat_map(actions(), & &1.signal_definitions())

  @doc "Return the incoming fact definitions."
  @spec event_definitions() :: [module()]
  def event_definitions do
    [
      Jido.Chat.Signal.MessageReceived,
      Jido.Chat.Signal.MessageUpdated,
      Jido.Chat.Signal.MessageDeleted,
      Jido.Chat.Signal.ReactionAdded,
      Jido.Chat.Signal.ReactionRemoved,
      Jido.Chat.Signal.ThreadStarted,
      Jido.Chat.Signal.SlashCommandReceived,
      Jido.Chat.Signal.ActionReceived,
      Jido.Chat.Signal.ModalSubmitted,
      Jido.Chat.Signal.NormalizationFailed
    ]
  end

  @doc "Build a catalog with core Chat and native Discord definitions."
  @spec catalog() :: Jido.Signal.Catalog.t()
  def catalog, do: Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions() ++ signal_definitions())
end
