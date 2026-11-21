defmodule Jido.Chat.Telegram.ActionHelpers do
  @moduledoc false

  @doc "Executes a test Action and returns its Signal reply."
  @spec execute(module(), term(), map(), keyword()) :: term()
  def execute(action, request, context, opts \\ [])

  def execute(action, %Jido.Signal{} = request, context, opts) do
    with {:ok, data} <- Jido.Exec.run(action, request.data, Map.put(context, :signal, request), opts),
         {:ok, signal} <- reply(action, request, data, context) do
      {:ok, %{signal: signal}}
    end
  end

  def execute(action, _request, context, opts), do: Jido.Exec.run(action, nil, context, opts)

  @doc "Builds a test Signal reply for an Action result."
  @spec reply(module(), Jido.Signal.t(), map(), map()) :: term()
  def reply(action, request, data, context) do
    subject =
      request.subject ||
        if request.data["room_id"],
          do: Jido.Chat.Signal.Identity.conversation_subject(context.client.id, request.data["room_id"])

    action.reply(request, data, source: context.client.source, subject: subject)
  end
end
