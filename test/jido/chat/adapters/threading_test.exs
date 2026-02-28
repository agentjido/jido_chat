defmodule Jido.Chat.Adapters.ThreadingTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Adapters.Threading

  defmodule ChannelWithThreading do
    @behaviour Threading

    @impl true
    def supports_threads?, do: true

    @impl true
    def compute_thread_root(raw), do: raw["thread_ts"] || raw["ts"]

    @impl true
    def extract_thread_context(raw) do
      %{
        thread_id: raw["thread_ts"],
        is_thread_reply: raw["thread_ts"] != nil,
        thread_root_ts: raw["thread_ts"] || raw["ts"]
      }
    end
  end

  test "supports_threads?/1" do
    assert Threading.supports_threads?(ChannelWithThreading)
    refute Threading.supports_threads?(String)
  end

  test "compute_thread_root/2" do
    assert Threading.compute_thread_root(ChannelWithThreading, %{"thread_ts" => "a", "ts" => "b"}) ==
             "a"

    assert Threading.compute_thread_root(String, %{"thread_ts" => "a"}) == nil
  end

  test "extract_thread_context/2" do
    assert Threading.extract_thread_context(ChannelWithThreading, %{
             "thread_ts" => "a",
             "ts" => "b"
           }) == %{
             thread_id: "a",
             is_thread_reply: true,
             thread_root_ts: "a"
           }

    assert Threading.extract_thread_context(String, %{"thread_ts" => "a"}) == %{}
  end
end
