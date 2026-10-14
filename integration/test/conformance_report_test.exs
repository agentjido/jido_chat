defmodule Jido.Chat.Integration.ConformanceReportTest do
  use ExUnit.Case, async: true

  test "missing evidence fails every row and cannot become an overall pass" do
    absent = Path.join(System.tmp_dir!(), "absent-g7-#{System.unique_integer([:positive])}")
    result = Jido.Chat.Integration.Conformance.run(evidence_directory: absent)
    assert result.state == "fail"

    assert Map.keys(result.assertions) |> Enum.sort() ==
             Enum.map(1..14, &("C" <> String.pad_leading(to_string(&1), 2, "0")))

    assert Enum.all?(result.assertions, fn {_, row} -> row.state == "fail" end)
  end

  test "all frozen support claims have named operation and event fixtures" do
    directory = Path.expand("../fixtures", __DIR__)
    operations = Jason.decode!(File.read!(Path.join(directory, "conformance-operations.json")))
    events = Jason.decode!(File.read!(Path.join(directory, "conformance-events.json")))
    assert map_size(operations) == 9
    assert Enum.all?(operations, fn {_, rows} -> map_size(rows) == 26 end)
    assert Enum.all?(events, fn {_, rows} -> map_size(rows) == 17 end)

    for {_, rows} <- operations, {_, row} <- rows do
      assert row["category"] == "fixtures"
      assert String.contains?(row["name"], "result")
      assert row["support"] in ["native", "fallback", "unsupported"]
    end
  end

  test "incomplete inputs return failed rows instead of raising" do
    directory = Path.join(System.tmp_dir!(), "bad-g7-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    File.write!(Path.join(directory, "inputs.json"), Jason.encode!(%{mandatory_commands: nil}))

    assert %{state: "fail", assertions: assertions} =
             Jido.Chat.Integration.Conformance.run(evidence_directory: directory)

    assert Enum.all?(assertions, fn {_, row} -> row.state == "fail" end)
  end
end
