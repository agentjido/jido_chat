defmodule Jido.Chat.AdapterTestKit.MockTransport do
  @moduledoc """
  A deterministic provider-free transport for adapter tests.

  The transport records calls in order. A response queue can be set for each
  operation. When a queue is empty, `request/4` returns its supplied default.
  """

  use GenServer

  @type operation :: atom()
  @type call :: %{operation: operation(), payload: term(), sequence: pos_integer()}
  @type server :: GenServer.server()

  @doc "Starts a mock transport."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    responses = opts |> Keyword.get(:responses, %{}) |> normalize_responses()
    GenServer.start_link(__MODULE__, responses, Keyword.take(opts, [:name]))
  end

  @doc "Records a request and returns the next queued response or the default."
  @spec request(server(), operation(), term(), term()) :: term()
  def request(server, operation, payload, default \\ {:error, :unstubbed}) do
    GenServer.call(server, {:request, operation, payload, default})
  end

  @doc "Replaces the response queue for an operation."
  @spec stub(server(), operation(), term() | [term()]) :: :ok
  def stub(server, operation, responses) do
    GenServer.call(server, {:stub, operation, List.wrap(responses)})
  end

  @doc "Returns all calls, or only calls for one operation."
  @spec calls(server(), operation() | nil) :: [call()]
  def calls(server, operation \\ nil), do: GenServer.call(server, {:calls, operation})

  @doc "Clears recorded calls and queued responses."
  @spec reset(server()) :: :ok
  def reset(server), do: GenServer.call(server, :reset)

  @impl true
  def init(responses), do: {:ok, %{calls: [], responses: responses, sequence: 0}}

  @impl true
  def handle_call({:request, operation, payload, default}, _from, state) do
    sequence = state.sequence + 1
    call = %{operation: operation, payload: payload, sequence: sequence}
    {response, responses} = pop_response(state.responses, operation, default, payload)

    {:reply, response, %{state | calls: [call | state.calls], responses: responses, sequence: sequence}}
  end

  def handle_call({:stub, operation, responses}, _from, state) do
    {:reply, :ok, %{state | responses: Map.put(state.responses, operation, responses)}}
  end

  def handle_call({:calls, operation}, _from, state) do
    calls =
      if is_nil(operation) do
        Enum.reverse(state.calls)
      else
        state.calls
        |> Enum.filter(&(&1.operation == operation))
        |> Enum.reverse()
      end

    {:reply, calls, state}
  end

  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{calls: [], responses: %{}, sequence: 0}}
  end

  defp pop_response(responses, operation, default, payload) do
    case Map.get(responses, operation, []) do
      [response | rest] -> {resolve(response, payload), Map.put(responses, operation, rest)}
      [] -> {resolve(default, payload), responses}
    end
  end

  defp resolve(fun, payload) when is_function(fun, 1), do: fun.(payload)
  defp resolve(fun, _payload) when is_function(fun, 0), do: fun.()
  defp resolve(response, _payload), do: response

  defp normalize_responses(responses) do
    Map.new(responses, fn {operation, values} -> {operation, List.wrap(values)} end)
  end
end
