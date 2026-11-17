defmodule Jido.Chat.Runtime.Storage.Reactions do
  @moduledoc """
  Storage capability for current durable Room reaction state.

  Results use ascending message ID, reaction, and actor-key order. `:after` is
  an exclusive reaction record ID cursor. One query accepts at most 100 message
  IDs and returns at most 1,000 records.
  """

  alias Jido.Chat.Runtime.Room.Reaction

  @type query_option ::
          {:message_id, String.t()}
          | {:message_ids, [String.t()]}
          | {:status, Reaction.status()}
          | {:after, String.t()}
          | {:limit, pos_integer()}

  @callback insert_reaction(term(), Reaction.t()) :: {:ok, Reaction.t()} | {:error, term()}
  @callback get_reaction(term(), String.t(), String.t(), String.t(), String.t()) ::
              {:ok, Reaction.t() | nil} | {:error, term()}
  @callback list_reactions(term(), String.t(), [query_option()]) ::
              {:ok, [Reaction.t()]} | {:error, term()}
  @callback update_reaction(
              term(),
              String.t(),
              String.t(),
              String.t(),
              String.t(),
              pos_integer(),
              Reaction.t()
            ) :: {:ok, Reaction.t()} | {:error, term()}
end
