defmodule Jido.Chat.LiveCase.Formatter do
  @moduledoc false
  use GenServer

  def init(_opts), do: {:ok, nil}

  def handle_cast({:test_finished, %{tags: %{live_report: true, live_provider: provider, live_case: id}} = test}, state) do
    case outcome(test.state, test.tags.live_status) do
      nil -> :ok
      {status, reason} -> IO.puts("LIVE #{provider} #{id} #{status}#{reason}")
    end

    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}

  defp outcome(nil, :ready), do: {:passed, ""}
  defp outcome({:excluded, _}, _), do: nil
  defp outcome({:skipped, _}, {status, reason}), do: {status, " — " <> reason}

  defp outcome({:failed, failures}, _) do
    Enum.find_value(failures, {:failed, ""}, fn
      {_, %ExUnit.AssertionError{message: "live setup blocked: " <> reason}, _} ->
        {:blocked, " — " <> reason}

      {_, %ExUnit.AssertionError{message: "live check failed: " <> reason}, _} ->
        {:failed, " — " <> reason}

      _ ->
        nil
    end)
  end

  defp outcome(_, _), do: {:failed, ""}
end
