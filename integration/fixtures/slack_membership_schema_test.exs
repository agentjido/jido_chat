defmodule Jido.Chat.Integration.SlackMembershipSchemaTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.Signal.{Identity, MembershipChanged}

  @fixtures Path.join(__DIR__, "slack_membership_partial.json")
            |> File.read!()
            |> Jason.decode!()
            |> Map.fetch!("cases")

  for {fixture, index} <- Enum.with_index(@fixtures) do
    test "Slack partial fixture: #{fixture["name"]}" do
      fixture = unquote(Macro.escape(fixture))

      data =
        Map.merge(fixture["normalized"], %{
          "delivery_id" => "slack-partial",
          "item_id" => Integer.to_string(unquote(index))
        })

      assert {:ok, signal} =
               MembershipChanged.new(data,
                 source: Identity.binding_source("slack-fixture"),
                 subject: Identity.conversation_subject("slack-fixture", "C1")
               )

      catalog = Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions())
      assert {:ok, json} = Jido.Signal.Serialization.serialize(signal)
      assert {:ok, ^signal} = Jido.Signal.Catalog.decode(catalog, json)
      assert signal.data["previous"] == nil
      assert signal.data["participant_id"] == fixture["provider"]["user"]
      actor = fixture["provider"]["inviter"]
      assert signal.data["actor_id"] == if(actor in [nil, ""], do: nil, else: actor)
      refute Map.has_key?(signal.data, "complete")
      refute Map.has_key?(signal.data, "grant")
      if fixture["provider"]["type"] == "member_left_channel", do: assert(signal.data["transition"] == "left")
      refute signal.data["transition"] == "removed"
    end
  end

  test "partial state cannot introduce provider permissions or raw payload fields" do
    fixture = hd(@fixtures)
    data = Map.merge(fixture["normalized"], %{"delivery_id" => "slack-partial", "item_id" => "invalid"})

    for key <- ["raw", "token", "credentials", "grant", "complete"] do
      assert {:error, %Jido.Chat.Errors.Contract{}} = MembershipChanged.new(Map.put(data, key, true))
    end
  end
end
