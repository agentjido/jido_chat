defmodule Jido.Chat.ValueBoundariesTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.Errors.Validation

  test "serialization removes structs and preserves nested date, set, tuple and regex values" do
    metadata = %{
      datetime: ~U[2026-01-01 00:00:00Z],
      naive: ~N[2026-01-01 00:00:00],
      set: MapSet.new(["one"]),
      tuple: {"one", "two"},
      matcher: ~r/hello/i,
      nested: %{"__struct__" => "discard", :__struct__ => "discard", :value => "keep"}
    }

    map = Jido.Chat.Wire.to_plain(%{body: metadata})

    assert map["body"] == %{
             "datetime" => "2026-01-01T00:00:00Z",
             "naive" => "2026-01-01T00:00:00",
             "set" => ["one"],
             "tuple" => ["one", "two"],
             "matcher" => %{"source" => "hello", "opts" => Regex.opts(~r/hello/i)},
             "nested" => %{"value" => "keep"}
           }

    assert Jason.decode!(Jason.encode!(map))["body"]["matcher"]["source"] == "hello"
  end

  test "validation errors identify their subject and each invalid field" do
    assert Exception.message(Validation.exception(subject: nil, errors: [])) == "invalid data"
    assert Exception.message(Validation.exception(subject: "request", errors: nil)) == "invalid request"

    error =
      Validation.exception(
        subject: Jido.Chat.Card,
        errors: [
          %Zoi.Error{message: "is invalid", path: [:items, 0, :name]},
          %Zoi.Error{message: "is missing", path: []},
          %{message: "provider message"},
          :unknown
        ]
      )

    assert Exception.message(error) ==
             "invalid Jido.Chat.Card: items.0.name: is invalid; is missing; provider message; :unknown"
  end

  test "validation errors do not retain rejected input values" do
    input = %{kind: :unknown, text: String.duplicate("private", 600_000)}
    error = assert_raise Validation, fn -> Jido.Chat.Card.Component.new(input) end

    assert Exception.message(error) =~ "kind:"
    assert :erlang.external_size(error) < 10_000
    refute inspect(error) =~ "private"
  end
end
