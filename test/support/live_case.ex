defmodule Jido.Chat.LiveCase do
  @moduledoc false

  alias Jido.Chat
  alias Jido.Chat.AdapterTestKit.Assertions

  @providers ~w(telegram discord slack signal x)
  @selector "JIDO_CHAT_LIVE_PROVIDERS"
  @enabled ~w(1 true TRUE yes on)
  @halts %{unauthorized: 1, rate_limited: 2, uncertain_write: 3}

  defmacro __using__(opts) do
    profile = opts |> Keyword.fetch!(:profile) |> Macro.expand(__CALLER__)
    mode = Keyword.get(opts, :mode, :shared)
    group = Keyword.get(opts, :group)
    legacy_tag = Keyword.get(opts, :legacy_tag)

    quote bind_quoted: [profile: profile, mode: mode, group: group, legacy_tag: legacy_tag] do
      use ExUnit.Case, async: false

      alias Jido.Chat.LiveCase

      @profile profile
      @mode mode
      @group group
      @provider @profile.provider()
      @moduletag :live
      @moduletag live_provider: @provider
      if legacy_tag, do: @moduletag(legacy_tag)

      setup_all do
        %{live_stop: LiveCase.provider_halt(@provider)}
      end

      @moduletag live_report: LiveCase.selected?(@profile, @mode)

      for %{id: id, name: name} = spec <- @profile.cases(),
          is_nil(@group) or spec.group == @group do
        status = LiveCase.eligibility(@profile, spec, @mode)
        @tag live_case: id
        if id in LiveCase.Baseline.ids(), do: @tag(:live_baseline)
        if spec.manual, do: @tag(live_ui: true)
        @tag live_status: status
        @tag timeout: spec.timeout
        @tag skip: LiveCase.skip_reason(status)
        test "#{id} #{name}", %{live_stop: stop} do
          LiveCase.run(@profile, unquote(Macro.escape(spec)), stop, @mode)
        end
      end
    end
  end

  def init_halts do
    # Both legacy groups and the shared suite use the same stop state during a run.
    :persistent_term.put(__MODULE__, Map.new(@providers, &{&1, :atomics.new(1, [])}))
    ExUnit.after_suite(fn _ -> :persistent_term.erase(__MODULE__) end)
  end

  def provider_halt(provider), do: :persistent_term.get(__MODULE__) |> Map.fetch!(provider)

  def halt(stop, reason) do
    code = Map.fetch!(@halts, reason)

    case :atomics.compare_exchange(stop, 1, 0, code) do
      previous when previous == @halts.uncertain_write and reason != :uncertain_write ->
        :atomics.compare_exchange(stop, 1, previous, code)

      result ->
        result
    end
  end

  def halted?(stop), do: :atomics.get(stop, 1) != 0
  def cleanup_allowed?(stop), do: :atomics.get(stop, 1) in [0, @halts.uncertain_write]

  defp halt_reason(stop) do
    case :atomics.get(stop, 1) do
      1 -> "provider rejected the test credentials"
      2 -> "provider rate limit stopped the run"
      3 -> "a provider write has an uncertain outcome"
    end
  end

  def spec(group, id, name, body, opts \\ []) do
    %{
      group: group,
      id: id,
      name: name,
      body: body,
      operations: Keyword.get(opts, :operations, []),
      extensions: Keyword.get(opts, :extensions, []),
      events: Keyword.get(opts, :events, []),
      features: Keyword.get(opts, :features, []),
      target: Keyword.get(opts, :target, :room),
      manual: Keyword.get(opts, :manual),
      write: Keyword.get(opts, :write),
      unsupported: Keyword.get(opts, :unsupported),
      timeout: Keyword.get(opts, :timeout, 60_000)
    }
  end

  def selected_providers(value \\ System.get_env(@selector)) do
    providers = (value || "") |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    if Enum.any?(providers, &(&1 not in @providers)) do
      raise ArgumentError, "#{@selector} accepts #{Enum.join(@providers, ", ")}"
    end

    Enum.uniq(providers)
  end

  def legacy_enabled?(flag), do: selected_providers() == [] and enabled?(flag)
  def enabled?(flag), do: System.get_env(flag) in @enabled

  def selected?(profile, :shared), do: profile.provider() in selected_providers()
  def selected?(profile, :legacy), do: legacy_enabled?(profile.legacy_flag())
  def selected?(_profile, {:legacy, flag}), do: legacy_enabled?(flag)

  def eligibility(profile, spec, mode) do
    cond do
      not selected?(profile, mode) -> {:inactive, "provider or suite entry was not selected"}
      spec.manual && not enabled?(spec.manual) -> {:inactive, "set #{spec.manual}=true"}
      spec.write && not enabled?(spec.write) -> {:inactive, "set #{spec.write}=true"}
      true -> support(profile, spec)
    end
  end

  def support(_profile, %{unsupported: reason}) when is_binary(reason), do: {:unsupported, reason}

  def support(profile, spec) do
    adapter = profile.adapter()
    capabilities = Chat.Adapter.capabilities(adapter)
    actions = Enum.map(Chat.Adapter.operations(adapter), &elem(&1, 1))

    requirements =
      Enum.map(spec.operations, &{capabilities[&1] == :native, "operation", &1}) ++
        Enum.map(spec.extensions, &{&1 in actions, "extension", &1}) ++
        Enum.map(spec.events, &{&1 in Chat.Adapter.event_definitions(adapter), "event", &1}) ++
        Enum.map(spec.features, &{&1 in profile.features(), "feature", &1})

    case Enum.find(requirements, fn {supported?, _, _} -> not supported? end) do
      nil -> :ready
      {false, kind, requirement} -> {:unsupported, "#{kind} #{inspect(requirement)}"}
    end
  end

  def skip_reason(:ready), do: false
  def skip_reason({status, reason}), do: "#{status}: #{reason}"

  def run(profile, spec, stop, mode) do
    # ExUnit can override skip tags. The live flags still apply at execution time.
    case eligibility(profile, spec, mode) do
      :ready -> run_selected(profile, spec, stop)
      {status, reason} -> raise ExUnit.AssertionError, message: "live check #{status}: #{reason}"
    end
  end

  defp run_selected(profile, spec, stop) do
    run_id = "#{System.system_time(:microsecond)}-#{System.unique_integer([:positive])}"
    IO.puts("LIVE #{profile.provider()} #{spec.id} run=#{run_id}")

    with true <- spec.target == :none or not halted?(stop),
         {:ok, ctx} <- protect(fn -> profile.prepare(spec, run_id, stop) end) do
      {module, function} = spec.body

      case protect(fn -> apply(module, function, [ctx]) end, stop) do
        {:blocked, reason} -> blocked(reason)
        result -> result
      end
    else
      false -> blocked(halt_reason(stop))
      {:blocked, reason} -> blocked(reason)
    end
  rescue
    error in ExUnit.AssertionError ->
      case {failure_reason(stop), error.message} do
        {"provider rejected the test credentials" = reason, "live check failed" <> _} ->
          blocked(reason)

        {reason, "live check failed" <> _} when is_binary(reason) ->
          reraise ExUnit.AssertionError.exception(message: "live check failed: #{reason}"), __STACKTRACE__

        _ ->
          reraise error, __STACKTRACE__
      end
  end

  def failure_reason(stop) do
    if halted?(stop), do: halt_reason(stop)
  end

  def blocked(reason), do: raise(ExUnit.AssertionError, message: "live setup blocked: #{reason}")

  def on_cleanup(fun), do: ExUnit.Callbacks.on_exit(fn -> protect(fun) end)
  def on_cleanup(id, fun), do: ExUnit.Callbacks.on_exit(id, fn -> protect(fun) end)

  def required_env(name) do
    case String.trim(System.get_env(name) || "") do
      "" -> {:blocked, "set #{name}"}
      value -> {:ok, value}
    end
  end

  def dependency(:ok), do: :ok
  def dependency({:error, {:not_attempted, {:missing_dependency, app}}}), do: {:blocked, "missing dependency #{app}"}

  def provider_call(stop, kind, call) do
    if halted?(stop) and (kind != :cleanup or not cleanup_allowed?(stop)) do
      {:error, {:not_attempted, :live_run_stopped}}
    else
      result = call.()
      flag_result(stop, result)
      result
    end
  catch
    class, reason ->
      if kind != :read, do: halt(stop, :uncertain_write)
      :erlang.raise(class, reason, __STACKTRACE__)
  end

  def protect(fun, stop \\ nil) do
    {result, _captured_log} =
      ExUnit.CaptureLog.with_log(fn ->
        try do
          fun.()
        rescue
          error in ExUnit.AssertionError ->
            flag_result(stop, error.left)
            flag_result(stop, error.right)
            safe_failure("ExUnit.AssertionError", __STACKTRACE__)

          error ->
            safe_failure(inspect(error.__struct__), __STACKTRACE__)
        catch
          kind, _value -> safe_failure(to_string(kind), __STACKTRACE__)
        end
      end)

    result
  end

  @spec flag_result(:atomics.atomics_ref() | nil, term()) :: :ok | integer()
  def flag_result(nil, _result), do: :ok

  def flag_result(stop, {:error, %Chat.Error{code: code}})
      when code in [:unauthorized, :rate_limited],
      do: halt(stop, code)

  def flag_result(stop, {:error, {:rejected, code, _}})
      when code in [:unauthorized, :rate_limited],
      do: halt(stop, code)

  def flag_result(_stop, {:error, %Chat.Error{signal: %{data: %{"operation" => "jido.chat.query." <> _}}}}),
    do: :ok

  def flag_result(stop, {:error, %Chat.Error{signal: %{data: %{"outcome" => "unknown"}}}}),
    do: halt(stop, :uncertain_write)

  def flag_result(_, _), do: :ok

  defp safe_failure(kind, stack) do
    # Assertion values, transport errors and args may contain credentials or raw provider data.
    safe_stack =
      Enum.map(stack, fn
        {module, function, args, location} when is_list(args) -> {module, function, length(args), location}
        frame -> frame
      end)

    error = ExUnit.AssertionError.exception(message: "live check failed (#{kind}); see assertion location")
    reraise error, safe_stack
  end

  def assert_completion(client, signal, definition, request_id) do
    import ExUnit.Assertions
    signal = Assertions.assert_operation_success({:ok, signal}, Chat.catalog(client))
    assert signal.type == definition.type() <> ".completed"
    assert signal.data["operation"] == definition.type()
    assert signal.data["client_id"] == client.id
    assert signal.data["request_id"] == request_id
    assert is_binary(signal.extensions["jidocausationid"])
    assert :ok = Assertions.assert_json_round_trip(signal, Chat.catalog(client))
    signal.data["result"]
  end
end
