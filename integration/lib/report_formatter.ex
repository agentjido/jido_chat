defmodule Jido.Chat.Integration.ReportFormatter do
  @moduledoc false
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def init(_opts), do: {:ok, []}

  def handle_cast({:test_finished, test}, cases) do
    result = %{
      module: inspect(test.module),
      name: Atom.to_string(test.name),
      file: test.tags[:file],
      line: test.tags[:line],
      state: verdict(test.state)
    }

    {:noreply, [result | cases]}
  end

  def handle_cast({:suite_finished, _times}, cases) do
    path = System.fetch_env!("JIDO_CONFORMANCE_TEST_REPORT")
    results = Enum.sort_by(cases, &{&1.file, &1.line, &1.name})
    File.write!(path, Jason.encode!(%{cases: results}, pretty: true) <> "\n")
    {:noreply, cases}
  end

  def handle_cast(_event, cases), do: {:noreply, cases}

  defp verdict(nil), do: "pass"
  defp verdict({:failed, _}), do: "fail"
  defp verdict({:skipped, _}), do: "skipped"
  defp verdict({:excluded, _}), do: "excluded"
  defp verdict(_), do: "unknown"
end
