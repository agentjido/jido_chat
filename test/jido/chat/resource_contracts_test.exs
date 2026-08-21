defmodule Jido.Chat.ResourceContractsTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.{
    Adapter,
    Capabilities,
    ChannelRef,
    MessageSubject,
    Participant,
    Response,
    SentMessage,
    Thread,
    UserInfo
  }

  defmodule NativeAdapter do
    use Adapter

    @impl true
    def channel_type, do: :native_resource

    @impl true
    def transform_incoming(_payload), do: {:error, :not_implemented}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, Response.new(%{external_message_id: "m1", external_room_id: room_id})}
    end

    @impl true
    def get_user(user_id, opts) do
      send(self(), {:get_user, user_id, opts})

      {:ok,
       %{
         "id" => user_id,
         "username" => "octocat",
         "display_name" => "The Octocat",
         "email" => "octocat@example.com",
         "avatar_url" => "https://example.com/octocat.png",
         "metadata" => %{"provider" => "github"}
       }}
    end

    @impl true
    def fetch_subject(room_id, opts) do
      send(self(), {:fetch_subject, room_id, opts})

      {:ok,
       %{
         "type" => "pull_request",
         "id" => 38,
         "title" => "Add resource contracts",
         "url" => "https://github.com/agentjido/jido_chat/pull/38",
         "status" => "open",
         "metadata" => %{"draft" => false}
       }}
    end

    @impl true
    def get_thread_participants(room_id, opts) do
      send(self(), {:get_thread_participants, room_id, opts})

      {:ok,
       [
         %{
           "id" => "u1",
           "username" => "octocat",
           "display_name" => "The Octocat"
         },
         Participant.new(%{
           id: "agent-1",
           type: :agent,
           identity: %{display_name: "Review Bot"},
           external_ids: %{native_resource: "bot-1"}
         }),
         %{
           "id" => "system-1",
           "type" => "system",
           "identity" => %{"display_name" => "GitHub"},
           "external_ids" => %{"native_resource" => "system-1"}
         },
         %{
           "id" => "provider-bot-1",
           "type" => "Bot",
           "username" => "provider-bot",
           "is_bot" => true
         }
       ]}
    end

    @impl true
    def mark_as_read(room_id, message_id, opts) do
      send(self(), {:mark_as_read, room_id, message_id, opts})
      {:ok, %{receipt_id: "receipt-1"}}
    end

    @impl true
    def capabilities do
      %{
        send_message: :native,
        get_user: :native,
        fetch_subject: :native,
        get_thread_participants: :native,
        mark_as_read: :native
      }
    end
  end

  defmodule SubjectFallbackAdapter do
    use Adapter

    @impl true
    def channel_type, do: :subject_fallback

    @impl true
    def transform_incoming(_payload), do: {:error, :not_implemented}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, Response.new(%{external_message_id: "m1", external_room_id: room_id})}
    end

    @impl true
    def fetch_thread(room_id, opts) do
      send(self(), {:fetch_thread_for_subject, room_id, opts})

      {:ok,
       %{
         id: "subject_fallback:#{room_id}:#{opts[:external_thread_id]}",
         external_room_id: room_id,
         external_thread_id: opts[:external_thread_id],
         metadata: %{
           subject: %{
             type: :issue,
             id: "38",
             title: "Add resource contracts",
             url: "https://github.com/agentjido/jido_chat/issues/38",
             status: :open,
             metadata: %{labels: ["enhancement"]}
           }
         }
       }}
    end

    @impl true
    def capabilities, do: %{send_message: :native, fetch_thread: :native, fetch_subject: :fallback}
  end

  defmodule MalformedSubjectFallbackAdapter do
    use Adapter

    @impl true
    def channel_type, do: :malformed_subject_fallback

    @impl true
    def transform_incoming(_payload), do: {:error, :not_implemented}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, Response.new(%{external_message_id: "m1", external_room_id: room_id})}
    end

    @impl true
    def fetch_thread(room_id, opts) do
      send(self(), {:fetch_malformed_thread_for_subject, room_id, opts})
      {:ok, :invalid}
    end

    @impl true
    def capabilities, do: %{send_message: :native, fetch_thread: :native, fetch_subject: :fallback}
  end

  defmodule UnsupportedAdapter do
    use Adapter

    @impl true
    def channel_type, do: :unsupported_resource

    @impl true
    def transform_incoming(_payload), do: {:error, :not_implemented}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, Response.new(%{external_message_id: "m1", external_room_id: room_id})}
    end
  end

  defmodule InvalidDeclarationAdapter do
    use Adapter

    @impl true
    def channel_type, do: :invalid_resource

    @impl true
    def transform_incoming(_payload), do: {:error, :not_implemented}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, Response.new(%{external_message_id: "m1", external_room_id: room_id})}
    end

    @impl true
    def capabilities do
      %{
        send_message: :native,
        get_user: :native,
        fetch_subject: :native,
        get_thread_participants: :native,
        mark_as_read: :native
      }
    end
  end

  defmodule ProviderErrorAdapter do
    use Adapter

    @impl true
    def channel_type, do: :provider_error

    @impl true
    def transform_incoming(_payload), do: {:error, :not_implemented}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, Response.new(%{external_message_id: "m1", external_room_id: room_id})}
    end

    @impl true
    def get_user(_user_id, _opts), do: {:error, {:provider_error, 404}}

    @impl true
    def fetch_subject(_room_id, _opts), do: {:error, {:provider_error, 403}}

    @impl true
    def get_thread_participants(_room_id, _opts), do: {:error, {:provider_error, 429}}

    @impl true
    def mark_as_read(_room_id, _message_id, _opts), do: {:error, {:provider_error, 503}}
  end

  defmodule InvalidResultAdapter do
    use Adapter

    @impl true
    def channel_type, do: :invalid_result

    @impl true
    def transform_incoming(_payload), do: {:error, :not_implemented}

    @impl true
    def send_message(room_id, _text, _opts) do
      {:ok, Response.new(%{external_message_id: "m1", external_room_id: room_id})}
    end

    @impl true
    def get_user(_user_id, _opts), do: {:ok, %{}}

    @impl true
    def fetch_subject(_room_id, _opts), do: {:ok, %{}}

    @impl true
    def get_thread_participants(_room_id, _opts), do: {:ok, :not_a_list}

    @impl true
    def mark_as_read(_room_id, _message_id, _opts), do: {:ok}
  end

  test "UserInfo normalizes atom and string keyed input" do
    assert %UserInfo{
             id: "42",
             username: "ada",
             display_name: "Ada Lovelace",
             is_bot: false
           } =
             UserInfo.new(%{
               user_id: 42,
               user_name: "ada",
               full_name: "Ada Lovelace"
             })

    assert %UserInfo{id: "u2", username: "grace", is_bot: true} =
             UserInfo.new(%{"id" => "u2", "username" => "grace", "is_bot" => true})
  end

  test "MessageSubject normalizes atom and string keyed input" do
    assert %MessageSubject{
             type: "pull_request",
             id: "38",
             title: "Resource contracts",
             status: "open",
             metadata: %{"draft" => false}
           } =
             MessageSubject.new(%{
               "type" => "pull_request",
               "id" => 38,
               "title" => "Resource contracts",
               "url" => "https://example.com/pull/38",
               "status" => "open",
               "metadata" => %{"draft" => false}
             })
  end

  test "native callbacks return normalized public models" do
    assert {:ok, %UserInfo{id: "u1", username: "octocat"} = user} =
             Adapter.get_user(NativeAdapter, "u1", scope: :test)

    assert user.metadata == %{"provider" => "github"}
    assert_received {:get_user, "u1", scope: :test}

    assert {:ok, %MessageSubject{type: "pull_request", id: "38", status: "open"}} =
             Adapter.fetch_subject(NativeAdapter, "repo", external_thread_id: "38")

    assert_received {:fetch_subject, "repo", external_thread_id: "38"}

    assert {:ok,
            [
              %Participant{} = user_participant,
              %Participant{} = agent_participant,
              %Participant{} = system_participant,
              %Participant{} = provider_bot_participant
            ]} =
             Adapter.get_thread_participants(
               NativeAdapter,
               "repo",
               external_thread_id: "38"
             )

    assert user_participant.id == "u1"
    assert user_participant.type == :human
    assert user_participant.identity.username == "octocat"
    assert user_participant.external_ids.native_resource == "u1"
    assert agent_participant.id == "agent-1"
    assert system_participant.type == :system
    assert provider_bot_participant.type == :agent

    assert_received {:get_thread_participants, "repo", external_thread_id: "38"}

    assert :ok = Adapter.mark_as_read(NativeAdapter, "repo", "message-1", source: :test)
    assert_received {:mark_as_read, "repo", "message-1", source: :test}
    assert :read_receipts in Capabilities.channel_capabilities(NativeAdapter)
  end

  test "fetch_subject uses only an explicit subject from native thread metadata" do
    assert Adapter.capabilities(SubjectFallbackAdapter).fetch_subject == :fallback
    assert :ok = Adapter.validate_capabilities(SubjectFallbackAdapter)

    assert {:ok, %MessageSubject{type: "issue", id: "38", status: "open"}} =
             Adapter.fetch_subject(
               SubjectFallbackAdapter,
               "agentjido/jido_chat",
               external_thread_id: "38"
             )

    assert_received {:fetch_thread_for_subject, "agentjido/jido_chat", external_thread_id: "38"}
  end

  test "fetch_subject returns a stable error when its thread fallback is malformed" do
    assert {:error, :invalid_thread_result} =
             Adapter.fetch_subject(
               MalformedSubjectFallbackAdapter,
               "agentjido/jido_chat",
               external_thread_id: "38"
             )

    assert_received {
      :fetch_malformed_thread_for_subject,
      "agentjido/jido_chat",
      external_thread_id: "38"
    }
  end

  test "unsupported callbacks return an explicit unsupported error" do
    assert Adapter.capabilities(UnsupportedAdapter).get_user == :unsupported
    assert Adapter.capabilities(UnsupportedAdapter).fetch_subject == :unsupported
    assert Adapter.capabilities(UnsupportedAdapter).get_thread_participants == :unsupported
    assert Adapter.capabilities(UnsupportedAdapter).mark_as_read == :unsupported

    assert {:error, :unsupported} = Adapter.get_user(UnsupportedAdapter, "u1")
    assert {:error, :unsupported} = Adapter.fetch_subject(UnsupportedAdapter, "room")
    assert {:error, :unsupported} = Adapter.get_thread_participants(UnsupportedAdapter, "room")
    assert {:error, :unsupported} = Adapter.mark_as_read(UnsupportedAdapter, "room", "m1")
  end

  test "capability validation detects false native declarations" do
    assert {:error, {:invalid_capability_matrix, mismatches}} =
             Adapter.validate_capabilities(InvalidDeclarationAdapter)

    assert {:get_user, :missing_callback} in mismatches
    assert {:fetch_subject, :missing_callback} in mismatches
    assert {:get_thread_participants, :missing_callback} in mismatches
    assert {:mark_as_read, :missing_callback} in mismatches
  end

  test "provider errors pass through all safe wrappers" do
    assert {:error, {:provider_error, 404}} = Adapter.get_user(ProviderErrorAdapter, "u1")
    assert {:error, {:provider_error, 403}} = Adapter.fetch_subject(ProviderErrorAdapter, "room")

    assert {:error, {:provider_error, 429}} =
             Adapter.get_thread_participants(ProviderErrorAdapter, "room")

    assert {:error, {:provider_error, 503}} =
             Adapter.mark_as_read(ProviderErrorAdapter, "room", "m1")
  end

  test "invalid callback success values return stable contract errors" do
    assert {:error, :invalid_user_info_result} = Adapter.get_user(InvalidResultAdapter, "u1")
    assert {:error, :invalid_subject_result} = Adapter.fetch_subject(InvalidResultAdapter, "room")

    assert {:error, :invalid_thread_participants_result} =
             Adapter.get_thread_participants(InvalidResultAdapter, "room")

    assert {:error, :invalid_mark_as_read_result} =
             Adapter.mark_as_read(InvalidResultAdapter, "room", "m1")
  end

  test "channel, thread, and sent-message helpers route normalized operations" do
    channel =
      ChannelRef.new(%{
        id: "native_resource:repo",
        adapter_name: :native_resource,
        adapter: NativeAdapter,
        external_id: "repo"
      })

    thread =
      Thread.new(%{
        id: "native_resource:repo:38",
        adapter_name: :native_resource,
        adapter: NativeAdapter,
        external_room_id: "repo",
        external_thread_id: "38"
      })

    sent =
      SentMessage.new(%{
        id: "message-1",
        thread_id: thread.id,
        adapter: NativeAdapter,
        external_room_id: "repo",
        response: Response.new(%{external_message_id: "message-1", external_room_id: "repo"}),
        default_opts: [external_thread_id: "38"]
      })

    assert {:ok, %UserInfo{id: "u1"}} = ChannelRef.get_user(channel, "u1")
    assert_received {:get_user, "u1", external_room_id: "repo"}

    assert {:ok, %MessageSubject{id: "38"}} = Thread.fetch_subject(thread)
    assert_received {:fetch_subject, "repo", thread_id: "38"}

    assert {:ok, [%Participant{}, %Participant{}, %Participant{}, %Participant{}]} =
             Thread.participants(thread)

    assert_received {:get_thread_participants, "repo", thread_id: "38"}

    assert :ok = SentMessage.mark_as_read(sent)
    assert_received {:mark_as_read, "repo", "message-1", external_thread_id: "38"}

    assert :ok = SentMessage.mark_as_read(sent)
  end

  test "SentMessage.mark_as_read requires a provider external message id" do
    missing_external_id =
      SentMessage.new(%{
        id: "generated-local-id",
        thread_id: "native_resource:repo:38",
        adapter: NativeAdapter,
        external_room_id: "repo",
        response: Response.new(%{external_room_id: "repo"})
      })

    blank_external_id =
      SentMessage.new(%{
        id: "generated-local-id",
        thread_id: "native_resource:repo:38",
        adapter: NativeAdapter,
        external_room_id: "repo",
        response: Response.new(%{external_message_id: "   ", external_room_id: "repo"})
      })

    assert {:error, :missing_external_message_id} = SentMessage.mark_as_read(missing_external_id)
    refute_received {:mark_as_read, _, _, _}

    assert {:error, :missing_external_message_id} = SentMessage.mark_as_read(blank_external_id)
    refute_received {:mark_as_read, _, _, _}
  end

  test "UserInfo and MessageSubject serialize and revive" do
    user = UserInfo.new(%{id: "u1", username: "octocat", metadata: %{provider: :github}})

    subject =
      MessageSubject.new(%{
        type: :issue,
        id: "38",
        title: "Add resource contracts",
        status: :open,
        metadata: %{labels: ["enhancement"]}
      })

    assert %UserInfo{id: "u1", username: "octocat"} =
             user |> UserInfo.to_map() |> Jido.Chat.reviver().()

    assert %MessageSubject{type: "issue", id: "38", status: "open"} =
             subject |> MessageSubject.to_map() |> Jido.Chat.reviver().()
  end
end
