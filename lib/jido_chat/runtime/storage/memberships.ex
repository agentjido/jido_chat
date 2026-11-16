defmodule Jido.Chat.Runtime.Storage.Memberships do
  @moduledoc "Storage capability for durable Room membership."

  alias Jido.Chat.Runtime.Room.Membership

  @callback insert_membership(term(), Membership.t()) :: {:ok, Membership.t()} | {:error, term()}
  @callback get_membership(term(), String.t(), String.t()) ::
              {:ok, Membership.t() | nil} | {:error, term()}
  @callback list_memberships(term(), String.t(), keyword()) ::
              {:ok, [Membership.t()]} | {:error, term()}
  @callback update_membership(term(), String.t(), String.t(), pos_integer(), Membership.t()) ::
              {:ok, Membership.t()} | {:error, term()}
end
