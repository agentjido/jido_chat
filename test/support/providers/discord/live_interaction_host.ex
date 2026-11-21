defmodule Jido.Chat.Discord.LiveInteractionHost do
  @moduledoc false
  use GenServer
  alias Jido.Chat.Discord.LiveHelpers, as: L

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @doc false
  def put(private, host), do: GenServer.call(host, {:put, private})
  @doc false
  def respond(signal), do: GenServer.call(__MODULE__, {:respond, signal}, 5_000)

  @doc false
  def init({client, observer}) do
    Process.flag(:sensitive, true)
    Process.send_after(self(), :expire, 500)
    {:ok, %{client: client, observer: observer, controls: %{}}}
  end

  @doc false
  def handle_call({:put, control}, _, state) do
    # This bounded host store is an explicit test composition, not SDK state.
    if map_size(state.controls) < 100 do
      {:reply, :ok, %{state | controls: Map.put_new(state.controls, control.interaction_id, control)}}
    else
      {:reply, {:error, :full}, state}
    end
  end

  def handle_call({:respond, signal}, _, state) do
    {control, rest} = Map.pop(state.controls, signal.data["interaction_id"])
    {type, data} = response(signal)

    request =
      L.request(Jido.Chat.Discord.Signal.RespondInteraction, state.client, %{
        "room_id" => signal.data["room_id"],
        "interaction_id" => signal.data["interaction_id"],
        "response_type" => type,
        "data" => data
      })

    result = Jido.Chat.execute(state.client, request, options: [interaction: control])
    elapsed = if control, do: System.monotonic_time(:millisecond) - control.received_at, else: -1
    # The observer receives public values only.
    send(state.observer, {:interaction_result, signal, request, result, elapsed})
    {:reply, result, %{state | controls: rest}}
  end

  @doc false
  def handle_info(:expire, state) do
    now = System.monotonic_time(:millisecond)
    controls = Map.reject(state.controls, fn {_, c} -> now - c.received_at >= 3_000 end)
    Process.send_after(self(), :expire, 500)
    {:noreply, %{state | controls: controls}}
  end

  @doc false
  def format_status(status), do: status |> Map.put(:state, :redacted) |> Map.put(:message, :redacted)

  defp response(%{type: "jido.chat.action.received", data: %{"action_id" => "jido:modal"}}),
    do:
      {9,
       %{
         "custom_id" => "jido:proof-modal",
         "title" => "Jido modal proof",
         "components" => [
           %{
             "type" => 1,
             "components" => [
               %{"type" => 4, "custom_id" => "answer", "label" => "Proof value", "style" => 1, "required" => true}
             ]
           }
         ]
       }}

  defp response(%{type: "jido.chat.action.received"}), do: {7, %{"content" => "Jido callback proof passed"}}
  defp response(%{type: "jido.chat.modal.submitted"}), do: {4, %{"content" => "Jido modal proof passed", "flags" => 64}}
  defp response(_), do: {4, %{"content" => "Jido slash proof passed", "flags" => 64}}
end

defmodule Jido.Chat.Discord.LiveInteractionReply do
  @moduledoc false
  use Jido.Action, name: "discord_live_interaction_reply", schema: Zoi.map()

  @doc false
  def run(_params, context) do
    if context.signal.type in [
         "jido.chat.action.received",
         "jido.chat.modal.submitted",
         "jido.chat.slash_command.received"
       ] do
      case Jido.Chat.Discord.LiveInteractionHost.respond(context.signal) do
        {:ok, _} -> {:ok, %{context.agent_state | last_interaction: context.signal.data["interaction_id"]}}
        {:error, _} -> {:error, :interaction_failed}
      end
    else
      {:ok, context.agent_state}
    end
  end
end

defmodule Jido.Chat.Discord.LiveInteractionAgent do
  @moduledoc false
  use Jido.Agent, name: "discord_live_interaction_agent", plugins: [Jido.Chat.Plugin]

  state do
    schema(Jido.Joi.object(%{last_interaction: Zoi.string() |> Zoi.default("")}))
  end

  chat do
    connection :discord do
      client Jido.Chat.Discord.Adapter, id: "discord-live"
      rooms ["placeholder"]
      commands [Jido.Chat.Discord.RespondInteraction]
      source Jido.Chat.Discord.Source, emit: "jido.chat.**"
    end
  end

  routes do
    route("jido.chat.**", Jido.Chat.Discord.LiveInteractionReply)
  end
end
