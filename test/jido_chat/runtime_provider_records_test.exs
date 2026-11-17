defmodule Jido.Chat.RuntimeProviderRecordsTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Runtime.Bridge.{Binding, Bindings}
  alias Jido.Chat.Runtime.Connection.Declaration
  alias Jido.Chat.Runtime.{Data, SecretResolver}
  alias Jido.Chat.Runtime.Storage.Adapter
  alias Jido.Chat.Runtime.Storage.Bindings, as: BindingStorage

  defmodule Resolver do
    @behaviour SecretResolver

    @impl true
    def resolve(refs, context), do: {:ok, %{token: refs["token"], account: context.account_id}}
  end

  defmodule BadResolver do
    @behaviour SecretResolver

    @impl true
    def resolve(_refs, _context), do: :invalid
  end

  defmodule ThrowingResolver do
    @behaviour SecretResolver

    @impl true
    def resolve(_refs, _context), do: throw(:private_failure)
  end

  defmodule NoResolverCallback do
  end

  defmodule PagingBindings do
    use Adapter, capabilities: [BindingStorage]

    @impl BindingStorage
    def insert_binding(_resource, binding), do: {:ok, binding}

    @impl BindingStorage
    def get_binding(_resource, _account_id, _external_room_id), do: {:ok, nil}

    @impl BindingStorage
    def list_bindings(resource, account_id, opts) do
      page = for index <- 1..1_000, do: binding(account_id, index)

      case {resource, Keyword.get(opts, :after)} do
        {:paged, nil} -> {:ok, page}
        {:paged, "room-1000"} -> {:ok, [binding(account_id, 1_001)]}
        {:stalled, _after} -> {:ok, page}
        {_resource, _after} -> {:ok, []}
      end
    end

    @impl BindingStorage
    def update_binding(_resource, _account_id, _external_room_id, _revision, binding),
      do: {:ok, binding}

    defp binding(account_id, index) do
      Binding.new!(%{
        account_id: account_id,
        room_id: "team",
        external_room_id: "room-" <> String.pad_leading(Integer.to_string(index), 4, "0")
      })
    end
  end

  @context %{
    account_id: "support",
    definition_key: "provider",
    settings: %{},
    metadata: %{}
  }

  test "connection declarations normalize portable data and control revisions" do
    attrs = %{
      "account_id" => "support",
      "definition_key" => "provider",
      "desired" => "stopped",
      "secret_refs" => %{token: "vault://support"},
      "settings" => %{poll_interval: 250},
      "metadata" => %{owner: :support},
      "inserted_at" => "2026-11-16T10:00:00Z",
      "updated_at" => "2026-11-16T10:00:00Z"
    }

    assert {:ok, declaration} = Declaration.new(attrs)
    assert declaration.desired == :stopped
    assert declaration.secret_refs == %{"token" => "vault://support"}
    assert declaration.settings == %{"poll_interval" => 250}
    assert declaration.metadata == %{"owner" => "support"}
    assert {:ok, ^declaration} = Declaration.new(declaration)
    assert {:ok, ^declaration} = Declaration.set_desired(declaration, :stopped)

    assert {:ok, running} = Declaration.set_desired(declaration, :running)
    assert running.revision == 2
    assert running.desired == :running

    assert {:ok, updated} = Declaration.update(running, %{metadata: %{owner: "operations"}})
    assert updated.revision == 3
    assert updated.metadata == %{"owner" => "operations"}
    assert {:ok, ^updated} = Declaration.update(updated, %{metadata: updated.metadata})
    assert {:ok, ^updated} = updated |> Declaration.to_map() |> Declaration.from_map()
  end

  test "connection declarations reject unsafe or invalid state" do
    valid = %{account_id: "support", definition_key: "provider"}

    assert {:error, :invalid_connection_declaration} = Declaration.new(Map.put(valid, :extra, true))
    assert {:error, :invalid_secret_refs} = Declaration.new(Map.put(valid, :secret_refs, %{token: ""}))

    assert {:error, :invalid_connection_settings} =
             Declaration.new(Map.put(valid, :settings, %{value: self()}))

    assert {:error, :invalid_connection_metadata} =
             Declaration.new(Map.put(valid, :metadata, %{:owner => "one", "owner" => "two"}))

    assert {:error, :invalid_datetime} = Declaration.new(Map.put(valid, :inserted_at, "not-a-time"))
    assert {:error, :invalid_connection_declaration} = Declaration.new(Map.put(valid, :desired, :invalid))
    assert {:error, :invalid_connection_declaration} = Declaration.new(Map.put(valid, :revision, 0))
    assert {:error, :invalid_connection_declaration} = Declaration.new(:invalid)
    assert {:error, :invalid_connection_declaration} = Declaration.from_map(:invalid)
    assert {:error, :invalid_connection_declaration} = Declaration.set_desired(:invalid, :running)
    assert {:error, :invalid_connection_update} = Declaration.update(:invalid, %{})

    declaration = Declaration.new!(valid)
    assert {:error, :invalid_connection_update} = Declaration.update(declaration, %{})
    assert {:error, :invalid_connection_update} = Declaration.update(declaration, %{desired: :stopped})
    assert_raise ArgumentError, fn -> Declaration.new!(%{}) end
  end

  test "bridge bindings normalize portable data and control revisions" do
    attrs = %{
      "account_id" => "support",
      "room_id" => "team",
      "external_room_id" => "provider-room",
      "direction" => "outbound",
      "metadata" => %{owner: :support},
      "inserted_at" => "2026-11-16T10:00:00Z",
      "updated_at" => "2026-11-16T10:00:00Z"
    }

    assert {:ok, binding} = Binding.new(attrs)
    assert binding.direction == :outbound
    assert binding.enabled
    assert binding.metadata == %{"owner" => "support"}
    assert Binding.directions() == [:inbound, :outbound, :both]
    assert Binding.mapping_name(binding) == Binding.mapping_name(binding)
    assert {:ok, ^binding} = Binding.new(binding)
    assert {:ok, ^binding} = Binding.set_enabled(binding, true)

    assert {:ok, disabled} = Binding.set_enabled(binding, false)
    assert disabled.revision == 2
    refute disabled.enabled

    assert {:ok, updated} = Binding.update(disabled, %{room_id: "other", direction: :both})
    assert updated.revision == 3
    assert {:ok, ^updated} = Binding.update(updated, %{room_id: "other"})
    assert {:ok, ^updated} = updated |> Binding.to_map() |> Binding.from_map()
  end

  test "bridge bindings reject unsafe or invalid state" do
    valid = %{account_id: "support", room_id: "team", external_room_id: "provider-room"}

    assert {:error, :invalid_bridge_binding} = Binding.new(Map.put(valid, :extra, true))
    assert {:error, :invalid_binding_metadata} = Binding.new(Map.put(valid, :metadata, %{value: self()}))
    assert {:error, :invalid_datetime} = Binding.new(Map.put(valid, :updated_at, "not-a-time"))
    assert {:error, :invalid_bridge_binding} = Binding.new(Map.put(valid, :direction, :invalid))
    assert {:error, :invalid_bridge_binding} = Binding.new(Map.put(valid, :enabled, :yes))
    assert {:error, :invalid_bridge_binding} = Binding.new(:invalid)
    assert {:error, :invalid_bridge_binding} = Binding.from_map(:invalid)
    assert {:error, :invalid_binding_update} = Binding.update(:invalid, %{})
    assert {:error, :invalid_binding_update} = Binding.set_enabled(:invalid, true)

    binding = Binding.new!(valid)
    assert {:error, :invalid_binding_update} = Binding.update(binding, %{})
    assert {:error, :invalid_binding_update} = Binding.update(binding, %{account_id: "other"})
    assert {:error, :invalid_binding_update} = Binding.set_enabled(binding, :yes)
    assert_raise ArgumentError, fn -> Binding.new!(%{}) end
  end

  test "portable runtime data is bounded and collision safe" do
    assert {:ok, %{"owner" => "support", "values" => [1, true, nil]}} =
             Data.portable_map(%{owner: :support, values: [1, true, nil]}, :invalid)

    assert {:error, :invalid} = Data.portable_map(%{:owner => 1, "owner" => 2}, :invalid)
    assert {:error, :invalid} = Data.portable_map(%{"pid" => self()}, :invalid)
    assert {:error, :invalid} = Data.portable_map(deep_value(18), :invalid)
    assert {:error, :invalid} = Data.portable_map([], :invalid)
    assert {:ok, ~U[2026-11-16 10:00:00Z]} = Data.datetime("2026-11-16T10:00:00Z")
    assert {:error, :invalid_datetime} = Data.datetime(1)
    assert Data.utc?(~U[2026-11-16 10:00:00Z])
    refute Data.utc?(1)
    assert Data.valid_id?("value")
    refute Data.valid_id?("")
  end

  test "secret resolver calls are safe and do not expose failures" do
    assert {:ok, %{}} = SecretResolver.resolve(nil, %{}, @context)

    assert {:error, :secret_resolver_required} =
             SecretResolver.resolve(nil, %{"token" => "reference"}, @context)

    assert {:ok, %{token: "reference", account: "support"}} =
             SecretResolver.resolve(Resolver, %{"token" => "reference"}, @context)

    assert {:error, :invalid_secret_resolver} =
             SecretResolver.resolve(NoResolverCallback, %{"token" => "reference"}, @context)

    assert {:error, :secret_resolution_failed} =
             SecretResolver.resolve(BadResolver, %{"token" => "reference"}, @context)

    assert {:error, :secret_resolution_failed} =
             SecretResolver.resolve(ThrowingResolver, %{"token" => "reference"}, @context)

    assert {:error, :invalid_secret_resolver} =
             SecretResolver.resolve("resolver", %{"token" => "reference"}, @context)
  end

  test "binding collection keeps page order and stops a stalled adapter" do
    Code.ensure_loaded!(Jido.Chat.RuntimeProviderRecordsTest.PagedRuntime)
    Code.ensure_loaded!(Jido.Chat.RuntimeProviderRecordsTest.StalledRuntime)

    assert {:ok, bindings} =
             Bindings.list_all(Jido.Chat.RuntimeProviderRecordsTest.PagedRuntime, "support")

    assert length(bindings) == 1_001
    assert hd(bindings).external_room_id == "room-0001"
    assert List.last(bindings).external_room_id == "room-1001"

    assert {:error, :invalid_binding_page} =
             Bindings.list_all(Jido.Chat.RuntimeProviderRecordsTest.StalledRuntime, "support")
  end

  defmodule PagedRuntime do
    def storage, do: {Jido.Chat.RuntimeProviderRecordsTest.PagingBindings, :paged}
  end

  defmodule StalledRuntime do
    def storage, do: {Jido.Chat.RuntimeProviderRecordsTest.PagingBindings, :stalled}
  end

  defp deep_value(depth) do
    Enum.reduce(1..depth, %{"leaf" => true}, fn index, value ->
      %{Integer.to_string(index) => value}
    end)
  end
end
