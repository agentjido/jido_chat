defmodule Jido.Chat.AccessContractTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{Authorizer, IdentityProvider, IdentitySource, Principal}

  defmodule InvalidIdentityProvider do
    @behaviour IdentityProvider
    @impl true
    def resolve(_source, _context), do: {:ok, %{id: "host-user", kind: :human, attributes: %{"token" => "no"}}}
  end

  defmodule CrashingIdentityProvider do
    @behaviour IdentityProvider
    @impl true
    def resolve(_source, _context), do: raise("provider failure")
  end

  defmodule UnsafeIdentityErrorProvider do
    @behaviour IdentityProvider
    @impl true
    def resolve(_source, _context), do: {:error, %{token: "must-not-escape"}}
  end

  defmodule InvalidAuthorizer do
    @behaviour Authorizer
    @impl true
    def authorize(_principal, _action, _resource, _context), do: true
  end

  defmodule UnsafeAuthorizationError do
    @behaviour Authorizer
    @impl true
    def authorize(_principal, _action, _resource, _context), do: {:error, %{proof: "must-not-escape"}}
  end

  defmodule ThrowingAuthorizer do
    @behaviour Authorizer
    @impl true
    def authorize(_principal, _action, _resource, _context), do: throw(:authorization_failure)
  end

  defmodule DirectPrincipalProvider do
    @behaviour IdentityProvider
    @impl true
    def resolve(_source, _context), do: {:ok, Principal.new(%{id: "direct", kind: :human})}
  end

  defmodule InvalidResultProvider do
    @behaviour IdentityProvider
    @impl true
    def resolve(_source, _context), do: :invalid
  end

  defmodule ThrowingIdentityProvider do
    @behaviour IdentityProvider
    @impl true
    def resolve(_source, _context), do: throw(:identity_failure)
  end

  test "a Principal contains only bounded Chat identity fields" do
    principal =
      Principal.new(%{
        id: "host-user",
        kind: :human,
        display_name: "Host User",
        roles: ["member"],
        assurance: :verified,
        attributes: %{"department" => "support"}
      })

    assert principal.id == "host-user"
    assert principal.roles == ["member"]
    assert principal.assurance == :verified
    assert Principal.from_map(Principal.to_map(principal)) == principal
  end

  test "Principal schema rejects unsafe attribute depth, keys, and values" do
    deep = Enum.reduce(1..18, "value", fn level, value -> %{"level_#{level}" => value} end)

    assert is_map(Principal.schema())
    assert :ok = Principal.safe_attributes(%{"items" => [1, true, nil]}, [])
    assert {:error, _reason} = Principal.safe_attributes(deep, [])
    assert {:error, _reason} = Principal.safe_attributes(%{"owner" => self()}, [])
    assert {:error, _reason} = Principal.safe_attributes(%{1 => "value"}, [])

    assert_raise Jido.Chat.Errors.Validation, fn ->
      Principal.new(%{id: "agent", kind: :agent, agent_address: %{"version" => 1}})
    end

    assert_raise Jido.Chat.Errors.Validation, fn ->
      Principal.new(%{id: "agent", kind: :agent, agent_address: %{namespace: "missing-id"}})
    end
  end

  test "provider account scope is part of an external identity key" do
    left = source("account-a")
    right = source("account-b")

    refute IdentitySource.key(left) == IdentitySource.key(right)
    assert IdentitySource.from_map(IdentitySource.to_map(left)) == left
  end

  test "the static provider uses the complete provider identity key" do
    source = source("account-a")

    context = %{
      options: %{
        identities: %{
          IdentitySource.key(source) => %{id: "host-user", kind: :human, assurance: :verified}
        }
      }
    }

    assert {:ok, %Principal{id: "host-user"}} =
             IdentityProvider.resolve(Jido.Chat.IdentityProvider.Static, source, context)

    assert {:error, :identity_not_found} =
             IdentityProvider.resolve(Jido.Chat.IdentityProvider.Static, source("account-b"), context)
  end

  test "the function provider supports a small local resolver" do
    resolver = fn identity_source, _context ->
      {:ok, %{id: "host:" <> identity_source.external_id, kind: :human}}
    end

    assert {:ok, %Principal{id: "host:external-user"}} =
             IdentityProvider.resolve(Jido.Chat.IdentityProvider.Function, source("account-a"), %{
               options: %{resolver: resolver}
             })
  end

  test "identity provider failures and unsafe principals fail closed" do
    assert {:error, :invalid_principal} =
             IdentityProvider.resolve(InvalidIdentityProvider, source("account-a"), %{})

    assert {:error, :identity_provider_failed} =
             IdentityProvider.resolve(CrashingIdentityProvider, source("account-a"), %{})

    assert {:error, :identity_not_resolved} =
             IdentityProvider.resolve(UnsafeIdentityErrorProvider, source("account-a"), %{})

    assert {:error, :invalid_identity_provider} =
             IdentityProvider.resolve(String, source("account-a"), %{})

    assert {:ok, %Principal{id: "direct"}} =
             IdentityProvider.resolve(DirectPrincipalProvider, source("account-a"), %{})

    assert {:error, :invalid_identity_provider_result} =
             IdentityProvider.resolve(InvalidResultProvider, source("account-a"), %{})

    assert {:error, :identity_provider_failed} =
             IdentityProvider.resolve(ThrowingIdentityProvider, source("account-a"), %{})

    refute IdentityProvider.valid?(123)
    assert {:error, :invalid_identity_request} = IdentityProvider.resolve(DirectPrincipalProvider, :invalid, %{})
  end

  test "the trusted Agent provider binds the complete caller Address" do
    address = Jido.Agent.Address.new!(namespace: "test", partition: "west", id: "agent-a")
    source = IdentitySource.new(%{provider: "jido", account_id: "test", external_id: "agent-a"})

    assert {:ok, %Principal{kind: :agent, agent_address: ^address} = principal} =
             IdentityProvider.resolve(Jido.Chat.IdentityProvider.TrustedAgent, source, %{
               caller_context: %{actor: address}
             })

    assert Principal.from_map(Principal.to_map(principal)) == principal
  end

  test "authorization wrappers reject invalid results and failures" do
    principal = Principal.new(%{id: "host-user", kind: :human})
    resource = %{type: :room, id: "room-a"}

    assert {:error, :not_authorized} =
             Authorizer.authorize(Jido.Chat.Authorizer.DenyAll, principal, :room_read, resource, %{})

    assert {:error, :invalid_authorizer_result} =
             Authorizer.authorize(InvalidAuthorizer, principal, :room_read, resource, %{})

    assert {:error, :authorization_denied} =
             Authorizer.authorize(UnsafeAuthorizationError, principal, :room_read, resource, %{})

    assert {:error, :authorizer_failed} =
             Authorizer.authorize(ThrowingAuthorizer, principal, :room_read, resource, %{})

    refute Authorizer.valid?(123)

    assert {:error, :invalid_authorization_request} =
             Authorizer.authorize(Jido.Chat.Authorizer.DenyAll, :invalid, :room_read, resource, %{})
  end

  test "the Room authorizer preserves administrator and membership rules" do
    admin = Principal.new(%{id: "operator", kind: :human})
    member = Principal.new(%{id: "member", kind: :human})
    resource = %{type: :room, id: "room-a"}

    assert :ok =
             Authorizer.authorize(Jido.Chat.Authorizer.Room, admin, :room_join, resource, %{
               admin: "operator",
               members: [],
               member: "member"
             })

    assert :ok =
             Authorizer.authorize(Jido.Chat.Authorizer.Room, member, :message_post, resource, %{
               admin: "operator",
               members: ["member"],
               member: nil
             })

    assert :ok =
             Authorizer.authorize(Jido.Chat.Authorizer.Room, member, :message_post, resource, %{
               admin: "operator",
               actor_active?: true,
               member: nil
             })

    assert {:error, :not_authorized} =
             Authorizer.authorize(Jido.Chat.Authorizer.Room, member, :message_post, resource, %{
               admin: "operator",
               actor_active?: false,
               working_members: ["member"],
               member: nil
             })

    assert {:error, :not_authorized} =
             Authorizer.authorize(Jido.Chat.Authorizer.Room, member, :room_join, resource, %{
               admin: "operator",
               members: ["member"],
               member: "other"
             })
  end

  test "the Room role authorizer applies its bounded role policy" do
    moderator = Principal.new(%{id: "moderator", kind: :human, roles: ["moderator"]})
    resource = %{type: :room, id: "room-a"}

    assert :ok = Authorizer.authorize(Jido.Chat.Authorizer.RoomRoles, moderator, :message_delete, resource, %{})

    assert {:error, :not_authorized} =
             Authorizer.authorize(Jido.Chat.Authorizer.RoomRoles, moderator, :bridge_manage, resource, %{})
  end

  defp source(account_id) do
    IdentitySource.new(%{
      provider: "slack",
      account_id: account_id,
      external_id: "external-user",
      room_id: "room-a"
    })
  end
end
