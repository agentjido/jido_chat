defmodule Jido.Chat.CapabilityMatrixTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.CapabilityMatrix

  test "matrix maps normalize support values without creating unknown atoms" do
    matrix =
      CapabilityMatrix.new(%{
        "adapter_name" => :fixture,
        "matrix" => %{
          "send_message" => " native ",
          :fetch_message => :fallback,
          :get_user => "invalid-new-status-9231",
          :list_threads => "",
          :open_dm => :invalid,
          "" => :native,
          "new-unknown-capability-9231" => :native,
          12 => :native
        }
      })

    assert CapabilityMatrix.as_map(matrix) == %{
             send_message: :native,
             fetch_message: :fallback,
             get_user: :unsupported,
             list_threads: :unsupported,
             open_dm: :unsupported
           }

    assert CapabilityMatrix.status(matrix, :send_message) == :native
    assert CapabilityMatrix.status(matrix, :fetch_messages) == :unsupported
    assert_raise ArgumentError, fn -> String.to_existing_atom("new-unknown-capability-9231") end
    assert_raise ArgumentError, fn -> String.to_existing_atom("invalid-new-status-9231") end

    assert CapabilityMatrix.to_map(CapabilityMatrix.from_map(CapabilityMatrix.to_map(matrix))) ==
             CapabilityMatrix.to_map(matrix)
  end

  test "capability lists declare native support and invalid collections produce an empty matrix" do
    matrix = CapabilityMatrix.new(%{capabilities: [:send_message, "fetch_message", "", 12]})
    assert CapabilityMatrix.as_map(matrix) == %{send_message: :native, fetch_message: :native}
    assert CapabilityMatrix.as_map(CapabilityMatrix.new(%{capabilities: 12})) == %{}
    assert CapabilityMatrix.as_map(CapabilityMatrix.new(%{})) == %{}
    assert Zoi.parse(CapabilityMatrix.schema(), %{capabilities: :invalid}) |> elem(0) == :error
  end
end
