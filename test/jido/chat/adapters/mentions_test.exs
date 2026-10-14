defmodule Jido.Chat.Adapters.MentionsTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Adapters.Mentions

  defmodule FullMentionsAdapter do
    @behaviour Mentions

    @impl true
    def parse_mentions(_body, raw) do
      entities = raw["entities"] || []

      Enum.map(entities, fn entity ->
        %{
          user_id: to_string(entity["user_id"]),
          username: entity["username"],
          offset: entity["offset"],
          length: entity["length"]
        }
      end)
    end

    @impl true
    def strip_mentions(body, mentions), do: Mentions.default_strip_mentions(body, mentions)

    @impl true
    def was_mentioned?(raw, bot_id),
      do: Enum.any?(raw["entities"] || [], &(to_string(&1["user_id"]) == bot_id))
  end

  test "parse_mentions/3 and normalize_mentions/1" do
    raw = %{
      "entities" => [%{"user_id" => 123, "username" => "john", "offset" => 0, "length" => 5}]
    }

    assert [%{user_id: "123", username: "john", offset: 0, length: 5}] =
             Mentions.parse_mentions(FullMentionsAdapter, "@john", raw)
  end

  test "normalize_mentions/1 ignores invalid text fields and retains valid siblings" do
    valid = %{user_id: "one", username: "Ada", offset: 0, length: 4}

    for invalid <- [%{}, [%{}]], field <- [:user_id, :username] do
      atom_mention = Map.put(%{user_id: "two", username: "Bob", offset: 4, length: 4}, field, invalid)
      string_mention = Map.new(atom_mention, fn {key, value} -> {Atom.to_string(key), value} end)

      assert Mentions.normalize_mentions([valid, atom_mention, string_mention]) == [valid]
    end
  end

  test "normalize_mentions/1 retains supported text conversions" do
    assert Mentions.normalize_mentions([
             %{user_id: 123, username: :ada, offset: 0, length: 4},
             %{user_id: 1.5, username: ~c"Bob", offset: 4, length: 4},
             %{user_id: :carol, username: nil, offset: 8, length: 6}
           ]) == [
             %{user_id: "123", username: "ada", offset: 0, length: 4},
             %{user_id: "1.5", username: "Bob", offset: 4, length: 4},
             %{user_id: "carol", username: nil, offset: 8, length: 6}
           ]
  end

  test "strip_mentions/3" do
    mentions = [%{offset: 0, length: 5, user_id: "1", username: nil}]
    assert Mentions.strip_mentions(FullMentionsAdapter, "@john hi", mentions) == " hi"
  end

  test "was_mentioned?/3" do
    raw = %{"entities" => [%{"user_id" => 123}]}
    assert Mentions.was_mentioned?(FullMentionsAdapter, raw, "123")
    refute Mentions.was_mentioned?(FullMentionsAdapter, raw, "999")
  end
end
