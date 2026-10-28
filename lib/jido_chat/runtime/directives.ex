defmodule Jido.Chat.Runtime.Directives.Publish do
  @moduledoc false
  use Jido.Agent.Directive

  @schema Zoi.struct(__MODULE__, %{message: Zoi.struct(Jido.Signal)})
  @enforce_keys [:message]
  @type t :: %__MODULE__{message: Jido.Signal.t()}
  defstruct [:message]

  @impl true
  def validate(value), do: Zoi.parse(@schema, value)
end

defmodule Jido.Chat.Runtime.Directives.Receive do
  @moduledoc false
  use Jido.Agent.Directive

  @schema Zoi.struct(__MODULE__, %{
            message: Zoi.struct(Jido.Signal),
            reply: Zoi.struct(Jido.Signal) |> Zoi.nullable() |> Zoi.default(nil)
          })
  @enforce_keys [:message]
  @type t :: %__MODULE__{message: Jido.Signal.t(), reply: Jido.Signal.t() | nil}
  defstruct [:message, :reply]

  @impl true
  def validate(value), do: Zoi.parse(@schema, value)
end

defmodule Jido.Chat.Runtime.Directives.RelayInbound do
  @moduledoc false
  use Jido.Agent.Directive
  @enforce_keys [:work]
  @type t :: %__MODULE__{work: map()}
  defstruct [:work]

  @impl true
  def validate(%__MODULE__{work: %{id: id, kind: :inbound}} = directive)
      when is_binary(id) and id != "",
      do: {:ok, directive}

  def validate(_directive), do: {:error, :invalid_inbound_bridge_work}
end

defmodule Jido.Chat.Runtime.Directives.RelayOutbound do
  @moduledoc false
  use Jido.Agent.Directive
  @enforce_keys [:work]
  @type t :: %__MODULE__{work: map()}
  defstruct [:work]

  @impl true
  def validate(%__MODULE__{work: %{id: id, kind: :outbound}} = directive)
      when is_binary(id) and id != "",
      do: {:ok, directive}

  def validate(_directive), do: {:error, :invalid_outbound_bridge_work}
end

defmodule Jido.Chat.Runtime.Directives.CompleteOutbound do
  @moduledoc false
  use Jido.Agent.Directive
  @enforce_keys [:request_id, :outcome]
  @type t :: %__MODULE__{
          request_id: String.t(),
          outcome: :completed | :failed,
          result: map() | nil
        }
  defstruct [:request_id, :outcome, :result]

  @impl true
  def validate(%__MODULE__{request_id: id, outcome: outcome} = directive)
      when is_binary(id) and id != "" and outcome in [:completed, :failed],
      do: {:ok, directive}

  def validate(_directive), do: {:error, :invalid_outbound_completion}
end
