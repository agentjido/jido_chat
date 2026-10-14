defmodule Jido.Chat.DomainBoundariesTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{FetchOptions, OptionsLoadOption, OptionsLoadOptionGroup, WebhookRequest, WebhookResponse}
  alias Jido.Chat.Errors.{Ingress, Validation}

  test "option groups retain ordered values and reject empty or invalid choices" do
    option = OptionsLoadOption.new(%{label: "One", value: "1", description: "First"})

    group =
      OptionsLoadOptionGroup.new(%{"label" => "Group", "options" => [option, %{"label" => "Two", "value" => "2"}]})

    assert Enum.map(group.options, & &1.value) == ["1", "2"]
    map = OptionsLoadOptionGroup.to_map(group)
    assert OptionsLoadOptionGroup.to_map(OptionsLoadOptionGroup.from_map(map)) == map
    assert OptionsLoadOptionGroup.new(group) == group
    assert OptionsLoadOption.new(option) == option
    assert OptionsLoadOption.from_map(OptionsLoadOption.to_map(option)) == option

    for attrs <- [%{label: "", value: "1"}, %{label: "One", value: ""}, %{label: "One"}] do
      assert_raise Validation, fn -> OptionsLoadOption.new(attrs) end
    end

    assert_raise Validation, fn -> OptionsLoadOptionGroup.new(%{label: "Group", options: []}) end
    assert Zoi.parse(OptionsLoadOption.schema(), %{label: "One"}) |> elem(0) == :error
    assert Zoi.parse(OptionsLoadOptionGroup.schema(), %{label: "Group", options: []}) |> elem(0) == :error
  end

  test "history options supply defaults and omit absent cursors from adapter options" do
    defaults = FetchOptions.new([])
    assert Map.new(FetchOptions.to_keyword(defaults)) == %{limit: 50, direction: :backward}
    opts = FetchOptions.new(cursor: "next", limit: 12, direction: :forward, metadata: %{source: "fixture"})
    assert Map.new(FetchOptions.to_keyword(opts)) == %{cursor: "next", limit: 12, direction: :forward}
    assert FetchOptions.new(opts) == opts
    assert_raise Validation, fn -> FetchOptions.new(%{direction: :invalid}) end
    assert Zoi.parse(FetchOptions.schema(), %{limit: "invalid"}) |> elem(0) == :error
  end

  test "raw webhook input is retained privately while header lookup ignores case" do
    raw = %{event: "message", headers: [{"X-Signature", "signature"}], method: "PUT", path: "/events"}
    request = WebhookRequest.new(raw)
    assert request.payload == raw
    assert request.raw == raw
    assert {request.method, request.path} == {"PUT", "/events"}
    assert WebhookRequest.header(request, "X-SIGNATURE") == "signature"
    assert WebhookRequest.header(request, "missing") == nil
    map = WebhookRequest.to_map(request)
    assert WebhookRequest.to_map(WebhookRequest.from_map(map)) == map
    assert Zoi.parse(WebhookRequest.schema(), %{method: 123}) |> elem(0) == :error
  end

  test "webhook response builders retain accepted bodies and readable error bodies" do
    assert WebhookResponse.accepted().body == %{ok: true}
    assert WebhookResponse.accepted(%{accepted: true}).body == %{accepted: true}

    for {body, expected} <- [
          {nil, %{error: "request_failed"}},
          {"invalid signature", %{error: "invalid signature"}},
          {%{code: "invalid"}, %{code: "invalid"}}
        ] do
      response = WebhookResponse.error(400, body)
      assert response.status == 400
      assert response.body == expected
      map = WebhookResponse.to_map(response)
      assert WebhookResponse.to_map(WebhookResponse.from_map(map)) == map
    end

    assert Zoi.parse(WebhookResponse.schema(), %{status: "invalid"}) |> elem(0) == :error
  end

  test "serialization removes structs and preserves nested date, set, tuple and regex values" do
    metadata = %{
      datetime: ~U[2026-01-01 00:00:00Z],
      naive: ~N[2026-01-01 00:00:00],
      set: MapSet.new(["one"]),
      tuple: {"one", "two"},
      matcher: ~r/hello/i,
      nested: %{"__struct__" => "discard", :__struct__ => "discard", :value => "keep"}
    }

    map = WebhookResponse.to_map(WebhookResponse.accepted(metadata))

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
        subject: FetchOptions,
        errors: [
          %Zoi.Error{message: "is invalid", path: [:items, 0, :name]},
          %Zoi.Error{message: "is missing", path: []},
          %{message: "provider message"},
          :unknown
        ]
      )

    assert Exception.message(error) ==
             "invalid Jido.Chat.FetchOptions: items.0.name: is invalid; is missing; provider message; :unknown"
  end

  test "ingress errors retain the transport, adapter and reason in their message" do
    assert Exception.message(Ingress.exception(transport: :webhook, adapter_name: :test, reason: :denied)) ==
             "ingress webhook routing failed for adapter test: :denied"

    assert Exception.message(Ingress.exception(transport: "custom", adapter_name: nil, reason: :denied)) ==
             "ingress \"custom\" routing failed for adapter unknown: :denied"

    assert Exception.message(Ingress.exception(transport: :gateway, adapter_name: "adapter", reason: :closed)) ==
             "ingress gateway routing failed for adapter adapter: :closed"
  end
end
