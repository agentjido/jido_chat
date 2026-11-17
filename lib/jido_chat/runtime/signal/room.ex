defmodule Jido.Chat.Runtime.Signal.Room do
  @moduledoc false

  @doc false
  def member_schema, do: Jido.Joi.union([Jido.Agent.Address.schema(), Jido.Joi.string() |> Jido.Joi.min(1)])

  @doc false
  def post_schema do
    Jido.Joi.map()
    |> Jido.Joi.refine({__MODULE__, :valid_post, []})
  end

  @doc false
  def message_schema do
    Jido.Joi.map()
    |> Jido.Joi.refine({__MODULE__, :valid_message, []})
  end

  @doc false
  def reaction_schema do
    Jido.Joi.string()
    |> Jido.Joi.min(1)
    |> Jido.Joi.max(256)
    |> Jido.Joi.refine({__MODULE__, :valid_reaction, []})
  end

  @doc false
  def reaction_message_id_schema do
    Jido.Joi.string()
    |> Jido.Joi.min(1)
    |> Jido.Joi.refine({__MODULE__, :valid_reaction_message_id, []})
  end

  @doc false
  def valid_reaction(value, _opts) do
    if byte_size(value) <= 256, do: :ok, else: {:error, "reaction exceeds 256 bytes"}
  end

  @doc false
  def valid_reaction_message_id(value, _opts) do
    if byte_size(value) <= 256, do: :ok, else: {:error, "message ID exceeds 256 bytes"}
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
    schema: Jido.Joi.map(%{"member" => Jido.Chat.Runtime.Signal.Room.member_schema()}, unrecognized_keys: :error)
end

defmodule Jido.Chat.Runtime.Signal.Room.Leave do
  @moduledoc "Removes a member through that member or the trusted room admin."
  use Jido.Signal,
    type: "jido.chat.room.leave",
    default_source: "urn:jido:chat:runtime:local",
    schema: Jido.Joi.map(%{"member" => Jido.Chat.Runtime.Signal.Room.member_schema()}, unrecognized_keys: :error)
end

defmodule Jido.Chat.Runtime.Signal.Room.Post do
  @moduledoc "Requests one portable Post. The trusted caller supplies its author."
  use Jido.Signal,
    type: "jido.chat.room.post",
    default_source: "urn:jido:chat:runtime:local",
    schema:
      Jido.Joi.map(
        %{
          "post" => Jido.Chat.Runtime.Signal.Room.post_schema(),
          "mentions" => Jido.Joi.list(Jido.Chat.Runtime.Signal.Room.member_schema()) |> Jido.Joi.default([])
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
      Jido.Joi.map(
        %{
          "room" => Jido.Agent.Address.schema(),
          "sequence" => Jido.Joi.integer() |> Jido.Joi.min(1),
          "author" => Jido.Chat.Runtime.Signal.Room.member_schema(),
          "message" => Jido.Chat.Runtime.Signal.Room.message_schema(),
          "mentions" => Jido.Joi.list(Jido.Chat.Runtime.Signal.Room.member_schema())
        },
        unrecognized_keys: :error
      )
end

defmodule Jido.Chat.Runtime.Signal.Room.AddReaction do
  @moduledoc "Requests an active reaction from the trusted caller on one retained message."
  use Jido.Signal,
    type: "jido.chat.room.reaction.add",
    default_source: "urn:jido:chat:runtime:local",
    schema:
      Jido.Joi.map(
        %{
          "message_id" => Jido.Chat.Runtime.Signal.Room.reaction_message_id_schema(),
          "reaction" => Jido.Chat.Runtime.Signal.Room.reaction_schema()
        },
        unrecognized_keys: :error
      )
end

defmodule Jido.Chat.Runtime.Signal.Room.RemoveReaction do
  @moduledoc "Requests removal of the trusted caller's reaction from one retained message."
  use Jido.Signal,
    type: "jido.chat.room.reaction.remove",
    default_source: "urn:jido:chat:runtime:local",
    schema:
      Jido.Joi.map(
        %{
          "message_id" => Jido.Chat.Runtime.Signal.Room.reaction_message_id_schema(),
          "reaction" => Jido.Chat.Runtime.Signal.Room.reaction_schema()
        },
        unrecognized_keys: :error
      )
end

defmodule Jido.Chat.Runtime.Signal.Room.CheckMember do
  @moduledoc "Checks membership and optional retained message through trusted caller context."
  use Jido.Signal,
    type: "jido.chat.room.check_member",
    default_source: "urn:jido:chat:runtime:local",
    schema:
      Jido.Joi.map(
        %{
          "member" => Jido.Chat.Runtime.Signal.Room.member_schema(),
          "message_id" => Jido.Joi.string() |> Jido.Joi.optional(),
          "message_data" => Jido.Joi.map() |> Jido.Joi.optional()
        },
        unrecognized_keys: :error
      )
end

defmodule Jido.Chat.Runtime.Signal.Room.MemberChecked do
  @moduledoc "Returns membership and retained-message evidence for one room turn."
  use Jido.Signal,
    type: "jido.chat.room.member_checked",
    default_source: "urn:jido:chat:runtime:room",
    schema: Jido.Joi.map(%{"member" => Jido.Joi.boolean(), "retained" => Jido.Joi.boolean()}, unrecognized_keys: :error)
end

defmodule Jido.Chat.Runtime.Signal.Room.Posted do
  @moduledoc "Returns the exact committed message fact for one Post request."
  use Jido.Signal,
    type: "jido.chat.room.posted",
    default_source: "urn:jido:chat:runtime:room",
    schema: Jido.Joi.map(%{"message" => Jido.Joi.struct(Jido.Signal)}, unrecognized_keys: :error)
end

defmodule Jido.Chat.Runtime.Signal.Room.ReactionChanged do
  @moduledoc "Returns durable reaction state and an optional newly committed canonical fact."
  use Jido.Signal,
    type: "jido.chat.room.reaction.changed",
    default_source: "urn:jido:chat:runtime:room",
    schema:
      Jido.Joi.map(
        %{
          "record_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "message_id" => Jido.Joi.string() |> Jido.Joi.min(1),
          "reaction" => Jido.Chat.Runtime.Signal.Room.reaction_schema(),
          "actor" => Jido.Chat.Runtime.Signal.Room.member_schema(),
          "status" => Jido.Joi.enum(["active", "removed"]),
          "revision" => Jido.Joi.integer() |> Jido.Joi.min(1),
          "changed" => Jido.Joi.boolean(),
          "fact" => Jido.Joi.struct(Jido.Signal) |> Jido.Joi.nullable()
        },
        unrecognized_keys: :error
      )
end
