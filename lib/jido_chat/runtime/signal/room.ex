defmodule Jido.Chat.Runtime.Signal.Room do
  @moduledoc false

  @doc false
  def post_schema do
    Zoi.map()
    |> Zoi.refine({__MODULE__, :valid_post, []})
  end

  @doc false
  def message_schema do
    Zoi.map()
    |> Zoi.refine({__MODULE__, :valid_message, []})
  end

  @doc false
  def valid_post(value, _opts) do
    Jido.Chat.Post.from_map(value)
    :ok
  rescue
    _ -> {:error, "expected a portable Jido.Chat.Post"}
  end

  @doc false
  def valid_message(value, _opts) do
    Jido.Chat.Message.from_map(value)
    :ok
  rescue
    _ -> {:error, "expected a portable Jido.Chat.Message"}
  end
end

defmodule Jido.Chat.Runtime.Signal.Room.Join do
  @moduledoc "Requests room membership through the trusted room admin."
  use Jido.Signal,
    type: "jido.chat.room.join",
    default_source: "urn:jido:chat:runtime:local",
    schema: Zoi.map(%{"member" => Jido.Chat.Runtime.Room.member_schema()}, unrecognized_keys: :error)
end

defmodule Jido.Chat.Runtime.Signal.Room.Leave do
  @moduledoc "Removes a member through that member or the trusted room admin."
  use Jido.Signal,
    type: "jido.chat.room.leave",
    default_source: "urn:jido:chat:runtime:local",
    schema: Zoi.map(%{"member" => Jido.Chat.Runtime.Room.member_schema()}, unrecognized_keys: :error)
end

defmodule Jido.Chat.Runtime.Signal.Room.Post do
  @moduledoc "Requests one portable Post. The trusted caller supplies its author."
  use Jido.Signal,
    type: "jido.chat.room.post",
    default_source: "urn:jido:chat:runtime:local",
    schema:
      Zoi.map(
        %{
          "post" => Jido.Chat.Runtime.Signal.Room.post_schema(),
          "mentions" => Zoi.list(Jido.Chat.Runtime.Room.member_schema()) |> Zoi.default([])
        },
        unrecognized_keys: :error
      )
end

defmodule Jido.Chat.Runtime.Signal.Room.Message do
  @moduledoc "Reports one committed portable room message."
  use Jido.Signal,
    type: "jido.chat.room.message",
    default_source: "urn:jido:chat:runtime:room",
    schema:
      Zoi.map(
        %{
          "room" => Jido.Agent.Ref.schema(),
          "sequence" => Zoi.integer() |> Zoi.min(1),
          "author" => Jido.Chat.Runtime.Room.member_schema(),
          "message" => Jido.Chat.Runtime.Signal.Room.message_schema(),
          "mentions" => Zoi.list(Jido.Chat.Runtime.Room.member_schema())
        },
        unrecognized_keys: :error
      )
end

defmodule Jido.Chat.Runtime.Signal.Room.CheckMember do
  @moduledoc "Reads room membership through the member's trusted caller context."
  use Jido.Signal,
    type: "jido.chat.room.check_member",
    default_source: "urn:jido:chat:runtime:local",
    schema: Zoi.map(%{"member" => Jido.Chat.Runtime.Room.member_schema()}, unrecognized_keys: :error)
end
