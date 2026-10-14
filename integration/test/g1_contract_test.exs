defmodule Jido.Chat.Integration.ContractTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Signal.Identity, as: ChatIdentity
  alias Jido.Messaging.Signal.Identity, as: RuntimeIdentity

  @directory Path.expand("../../docs/migration", __DIR__)
  @catalog @directory |> Path.join("catalog.json") |> File.read!() |> Jason.decode!()

  for entry <- @catalog["definitions"] do
    test "schema fixture #{entry["module"]} validates without a JSON projection" do
      entry = unquote(Macro.escape(entry))
      fixture = entry["fixture"]
      schema = Zoi.from_json_schema(entry["data_schema"])
      assert {:ok, ^fixture} = Zoi.parse(schema, fixture)
      assert Jason.decode!(Jason.encode!(fixture)) == fixture
      assert {:error, _} = Zoi.parse(schema, Map.put(fixture, "raw", %{"private" => true}))
    end
  end

  test "fixed identity encoding separates bindings, instances, rooms, and domain owners" do
    assert ChatIdentity.binding_source("binding/alpha") ==
             "urn:jido:chat:binding:YmluZGluZy9hbHBoYQ"

    assert ChatIdentity.conversation_subject("binding/alpha", "room/1") ==
             "conversation:YmluZGluZy9hbHBoYQ:cm9vbS8x"

    assert RuntimeIdentity.instance_source("instance/alpha") ==
             "urn:jido:messaging:instance:aW5zdGFuY2UvYWxwaGE"

    assert RuntimeIdentity.room_subject("room/one") == "room:cm9vbS9vbmU"
    assert RuntimeIdentity.room_subject(nil) == nil

    refute ChatIdentity.binding_source("alpha") == ChatIdentity.binding_source("beta")

    refute ChatIdentity.conversation_subject("alpha", "same") ==
             ChatIdentity.conversation_subject("beta", "same")

    refute RuntimeIdentity.room_subject("one") == RuntimeIdentity.room_subject("two")
    refute RuntimeIdentity.instance_source("alpha") == RuntimeIdentity.instance_source("beta")
    refute RuntimeIdentity.instance_source("alpha") == ChatIdentity.binding_source("alpha")
  end

  test "display-name changes do not enter the identity helper" do
    before = %{id: "room/one", name: "Old Name"}
    after_rename = %{before | name: "New Name"}

    assert RuntimeIdentity.room_subject(before.id) ==
             RuntimeIdentity.room_subject(after_rename.id)
  end

  test "invalid identity keys fail explicitly" do
    for invalid <- ["", <<255>>, nil, String.duplicate("a", 129)] do
      assert_raise ArgumentError, fn -> ChatIdentity.binding_source(invalid) end
      assert_raise ArgumentError, fn -> RuntimeIdentity.instance_source(invalid) end
    end
  end
end

defmodule Jido.Chat.Integration.ManifestTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Integration.Manifest
  @directory Path.expand("../../docs/migration", __DIR__)
  @names ~w(api-map catalog operations adapter-matrix version-matrix protocol gate-status)

  setup do
    manifests =
      Map.new(@names, fn name ->
        {name,
         @directory
         |> Path.join(name <> ".json")
         |> File.read!()
         |> Jason.decode!()
         |> Map.put("state", "frozen")}
      end)

    %{manifests: manifests}
  end

  test "the reviewed inventory satisfies the finite contract", %{manifests: manifests} do
    assert Manifest.contract_errors(manifests) == []
  end

  test "one missing operation or adapter cannot pass", %{manifests: manifests} do
    for {name, rows_key} <- [{"operations", "operations"}, {"adapter-matrix", "adapters"}] do
      broken = update_in(manifests, [name, rows_key], &tl/1)
      refute Manifest.contract_errors(broken) == []
    end
  end

  test "a duplicate schema pair or unsafe open data schema cannot pass", %{manifests: manifests} do
    rows = manifests["catalog"]["definitions"]
    duplicate = put_in(manifests, ["catalog", "definitions"], [hd(rows) | rows])
    refute Manifest.contract_errors(duplicate) == []

    unsafe =
      put_in(manifests, ["catalog", "definitions"], [
        %{hd(rows) | "data_schema" => %{}} | tl(rows)
      ])

    refute Manifest.contract_errors(unsafe) == []
  end

  test "invalid fixture data and unclassified public exports cannot pass", %{manifests: manifests} do
    [first | rest] = manifests["catalog"]["definitions"]

    broken =
      put_in(manifests, ["catalog", "definitions"], [
        %{first | "fixture" => %{"raw" => %{"token" => "private"}}} | rest
      ])

    refute Manifest.contract_errors(broken) == []

    [first | rest] = manifests["api-map"]["exports"]

    broken =
      put_in(manifests, ["api-map", "exports"], [%{first | "classification" => "pending"} | rest])

    refute Manifest.contract_errors(broken) == []
  end

  test "missing C01–C14 evidence cannot pass" do
    absent =
      Path.join(System.tmp_dir!(), "missing-conformance-#{System.unique_integer([:positive])}")

    assert %{state: "fail", assertions: assertions} =
             Jido.Chat.Integration.Conformance.run(evidence_directory: absent)

    assert map_size(assertions) == 14
    assert Enum.all?(assertions, fn {_id, row} -> row.state == "fail" end)
  end
end
