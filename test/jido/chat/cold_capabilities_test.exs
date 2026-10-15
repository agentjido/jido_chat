defmodule Jido.Chat.ColdCapabilitiesTest do
  use ExUnit.Case, async: false

  test "capability inspection loads a cold adapter before reading native support" do
    module = Module.concat([Jido.Chat, "ColdAdapter#{System.unique_integer([:positive])}"])

    [{^module, beam}] =
      Code.compile_string("""
      defmodule #{inspect(module)} do
        def capabilities, do: %{send_message: :native}
        def send_message(_room, _text, _opts), do: {:ok, "fixture"}
      end
      """)

    directory = Path.join(System.tmp_dir!(), "cold-capabilities-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    File.write!(Path.join(directory, Atom.to_string(module) <> ".beam"), beam)
    :code.purge(module)
    :code.delete(module)
    true = :code.add_patha(String.to_charlist(directory))

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
      :code.del_path(String.to_charlist(directory))
      File.rm_rf!(directory)
    end)

    refute function_exported?(module, :send_message, 3)
    assert Jido.Chat.Adapter.capabilities(module).send_message == :native
    assert :ok = Jido.Chat.Adapter.validate_capabilities(module)
  end
end
