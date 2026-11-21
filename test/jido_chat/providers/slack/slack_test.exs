defmodule Jido.Chat.SlackTest do
  use ExUnit.Case, async: true

  test "adapter/0 returns the slack adapter module" do
    assert Jido.Chat.Slack.adapter() == Jido.Chat.Slack.Adapter
  end
end
