defmodule Jido.Chat.SDKContractTest do
  use Covenant.Case, component: "jido_chat.sdk", async: true

  @tag obligation: "jido_chat.sdk.I1"
  test "the SDK declares no application callback, registered process, or Messaging dependency" do
    spec = Application.spec(:jido_chat)
    assert is_list(spec), "the compiled Chat application specification must be loaded"

    assert Keyword.get(spec, :mod, []) == [],
           "Chat must not start an application callback; the host owns its runtime"

    assert Keyword.get(spec, :registered, []) == [],
           "Chat must not declare registered processes; the host owns its runtime"

    refute :jido_messaging in Keyword.fetch!(spec, :applications),
           "the static SDK must not depend on the full Messaging system"
  end
end
