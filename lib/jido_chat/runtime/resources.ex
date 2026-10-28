defmodule Jido.Chat.Runtime.Resources do
  @moduledoc false

  @doc false
  @spec child_spec(Jido.Plugin.Init.t(), Supervisor.child_spec(), Jido.Agent.Ref.t()) ::
          Supervisor.child_spec()
  def child_spec(init, child, room) do
    {:ok, owner} = Jido.agent_ref(init.jido, init.agent_id, partition: init.partition)
    child = Supervisor.child_spec(child, id: {init.jido, owner, room})

    %{
      id: init.module,
      start: {Supervisor, :start_link, [[child], [strategy: :one_for_one]]},
      type: :supervisor
    }
  end

  @doc false
  @spec identity(pid()) :: {atom(), Jido.Agent.Ref.t(), Jido.Agent.Ref.t(), pid()}
  def identity(runtime) do
    [{{jido, owner, room}, child, _, _}] = Supervisor.which_children(runtime)
    {jido, owner, room, child}
  end

  @doc false
  @spec room_ref(Jido.Plugin.Init.t()) :: Jido.Agent.Ref.t()
  def room_ref(init) do
    case Keyword.fetch!(init.options, :room) do
      %Jido.Agent.Ref{namespace: namespace} = ref ->
        if namespace == Jido.namespace(init.jido),
          do: ref,
          else: raise(ArgumentError, "room must use the participant's Jido namespace")

      id when is_binary(id) ->
        {:ok, ref} = Jido.agent_ref(init.jido, id, partition: init.partition)
        ref
    end
  end
end
