defmodule Jido.Chat.OperationFailureTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Operations.Failure
  alias Jido.Chat.Signal.{OperationFailed, SendMessage}

  defmodule Adapter do
    def signal_protocol, do: 1
    def configure_binding(opts), do: {:ok, opts}
    def normalize_event(_binding, _request), do: {:error, :invalid_delivery}
    def capabilities, do: %{send_message: :native}
    def send_message(_room, _text, opts), do: {:error, opts[:reason]}
  end

  test "provider failures retain retry class without exposing private failure details" do
    reasons = [
      {%{class: :recoverable, reason: :private}, :recoverable},
      {%{class: :degraded}, :degraded},
      {%{class: :fatal}, :fatal},
      {%{reason: :timeout}, :recoverable},
      {:timeout, :recoverable},
      {:econnrefused, :recoverable},
      {:closed, :recoverable},
      {:nxdomain, :recoverable},
      {:network_error, :recoverable},
      {{:timeout, "private"}, :recoverable},
      {{:network_error, "private"}, :recoverable},
      {{:task_exit, "private"}, :recoverable},
      {{:exception, "private"}, :recoverable},
      {{:rate_limited, 429}, :recoverable},
      {{:api_error, :timeout}, :recoverable},
      {{:http_error, 503}, :recoverable},
      {{:http_status, 500}, :recoverable},
      {{:http_error, 400}, :fatal},
      {{:api_error, :denied}, :fatal},
      {:unsupported, :degraded},
      {{:unsupported, "private"}, :degraded},
      {{:unsupported_method, :send}, :degraded},
      {{:media_policy_denied, :image}, :degraded},
      {{:policy_denied, "private", :send, :room}, :degraded},
      {{:unknown, "private"}, :fatal}
    ]

    for {reason, expected_class} <- reasons do
      assert {:ok, binding} = Jido.Chat.bind(Adapter, id: "failure", reason: reason)
      request = SendMessage.new!(%{"request_id" => "one", "room_id" => "room", "text" => "hello"})
      assert {:ok, result} = Jido.Chat.execute(binding, request)
      assert result.type == OperationFailed.type()
      assert result.data["retryable"] == (expected_class == :recoverable)
      assert Failure.class(binding, result) == expected_class
      refute Jason.encode!(Jido.Signal.to_map(result)) =~ "private"
      assert {:ok, ^result} = Jido.Chat.execute(binding, request)
    end
  end

  test "terminal failure tags remain private and their class survives closed local storage" do
    for tag <- [:queue_full, :load_shed, :send_failed, :missing_external_message_id, :invalid_request],
        reason <- [tag, {tag, "private"}] do
      assert {:ok, binding} = Jido.Chat.bind(Adapter, id: "terminal", reason: reason)
      request = SendMessage.new!(%{"request_id" => "one", "room_id" => "room", "text" => "hello"})
      assert {:ok, result} = Jido.Chat.execute(binding, request)
      assert Failure.reason_tag(binding, result) == tag
      assert Failure.class(binding, result) == :fatal
      assert result.data["code"] == "provider_failure"
      assert :ok = Jido.Chat.Resources.close(binding)
      assert :ok = Failure.remember(binding, result, :fatal, tag)
      assert Failure.reason_tag(binding, result) == nil
      assert Failure.class(binding, result) == :fatal
    end
  end

  test "decoded failures recover their class when local metadata is absent" do
    for {code, retryable, expected} <- [
          {"provider_failure", true, :recoverable},
          {"unsupported", false, :degraded},
          {"provider_failure", false, :fatal}
        ] do
      assert {:ok, binding} = Jido.Chat.bind(Adapter, id: "decoded")

      result =
        OperationFailed.new!(%{
          "operation" => "send_message",
          "request_id" => "one",
          "code" => code,
          "retryable" => retryable
        })

      assert Failure.class(binding, result) == expected
      assert Failure.reason_tag(binding, result) == nil
      :ets.delete(binding.resources)
      assert Failure.class(binding, result) == expected
      assert Failure.reason_tag(binding, result) == nil
    end
  end
end
