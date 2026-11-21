defmodule Jido.Chat.Signal.Transport.CliClientTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.Signal.Transport.CliClient

  test "builds signal-cli attachment and quote arguments" do
    tmp_dir = System.tmp_dir!()
    args_path = Path.join(tmp_dir, "jido_signal_cli_args_#{System.unique_integer([:positive])}")
    executable = Path.join(tmp_dir, "jido_signal_cli_#{System.unique_integer([:positive])}.sh")

    File.write!(executable, """
    #!/bin/sh
    printf '%s\\n' "$@" > "$SIGNAL_CLI_TEST_ARGS"
    echo 1776000001
    """)

    File.chmod!(executable, 0o755)

    previous_args_path = System.get_env("SIGNAL_CLI_TEST_ARGS")
    System.put_env("SIGNAL_CLI_TEST_ARGS", args_path)

    on_exit(fn ->
      File.rm(executable)
      File.rm(args_path)

      if previous_args_path do
        System.put_env("SIGNAL_CLI_TEST_ARGS", previous_args_path)
      else
        System.delete_env("SIGNAL_CLI_TEST_ARGS")
      end
    end)

    assert {:ok, response} =
             CliClient.send_message("+15555550101", "+15555550100", "reply",
               executable: executable,
               attachments: [%{path: "/tmp/report.txt"}],
               reply_to_id: "1775999999",
               quote_author: "+15555550100",
               quote_message: "parent"
             )

    assert response["timestamp"] == "1776000001"

    assert File.read!(args_path) |> String.split("\n", trim: true) == [
             "-a",
             "+15555550101",
             "send",
             "-a",
             "/tmp/report.txt",
             "--quote-timestamp",
             "1775999999",
             "--quote-author",
             "+15555550100",
             "--quote-message",
             "parent",
             "-m",
             "reply",
             "+15555550100"
           ]
  end

  test "accepts data-backed file upload structs as data URI attachments" do
    tmp_dir = System.tmp_dir!()

    args_path =
      Path.join(tmp_dir, "jido_signal_cli_data_args_#{System.unique_integer([:positive])}")

    executable =
      Path.join(tmp_dir, "jido_signal_cli_data_#{System.unique_integer([:positive])}.sh")

    File.write!(executable, """
    #!/bin/sh
    printf '%s\\n' "$@" > "$SIGNAL_CLI_TEST_ARGS"
    echo 1776000002
    """)

    File.chmod!(executable, 0o755)

    previous_args_path = System.get_env("SIGNAL_CLI_TEST_ARGS")
    System.put_env("SIGNAL_CLI_TEST_ARGS", args_path)

    on_exit(fn ->
      File.rm(executable)
      File.rm(args_path)

      if previous_args_path do
        System.put_env("SIGNAL_CLI_TEST_ARGS", previous_args_path)
      else
        System.delete_env("SIGNAL_CLI_TEST_ARGS")
      end
    end)

    attachment = %{
      data: "R0lGODlhAQABAAAAACw=",
      filename: "tiny.gif",
      media_type: "image/gif"
    }

    assert {:ok, _response} =
             CliClient.send_message(nil, "+15555550100", "gif",
               executable: executable,
               attachments: [attachment]
             )

    assert [
             "send",
             "-a",
             "data:image/gif;filename=tiny.gif;base64,R0lGODlhAQABAAAAACw=",
             "-m",
             "gif",
             "+15555550100"
           ] = File.read!(args_path) |> String.split("\n", trim: true)
  end

  test "rejects remote attachments because signal-cli needs local files or data URIs" do
    assert {:error, {:unsupported_remote_attachment, "https://example.test/file.txt"}} =
             CliClient.send_message(nil, "+15555550100", "file",
               executable: "/does/not/matter",
               attachments: [%{url: "https://example.test/file.txt"}]
             )
  end

  test "receives line-delimited json envelopes with polling arguments" do
    tmp_dir = System.tmp_dir!()

    args_path =
      Path.join(tmp_dir, "jido_signal_cli_receive_args_#{System.unique_integer([:positive])}")

    executable =
      Path.join(tmp_dir, "jido_signal_cli_receive_#{System.unique_integer([:positive])}.sh")

    File.write!(executable, """
    #!/bin/sh
    printf '%s\\n' "$@" > "$SIGNAL_CLI_TEST_ARGS"
    printf '%s\\n' 'INFO  AccountHelper - The Signal protocol expects that incoming messages are regularly received.'
    printf '%s\\n' '{"envelope":{"timestamp":1776000003}}'
    printf '%s\\n' '{"envelope":{"timestamp":1776000004}}'
    """)

    File.chmod!(executable, 0o755)

    previous_args_path = System.get_env("SIGNAL_CLI_TEST_ARGS")
    System.put_env("SIGNAL_CLI_TEST_ARGS", args_path)

    on_exit(fn ->
      File.rm(executable)
      File.rm(args_path)

      if previous_args_path do
        System.put_env("SIGNAL_CLI_TEST_ARGS", previous_args_path)
      else
        System.delete_env("SIGNAL_CLI_TEST_ARGS")
      end
    end)

    assert {:ok,
            [
              %{"envelope" => %{"timestamp" => 1_776_000_003}},
              %{"envelope" => %{"timestamp" => 1_776_000_004}}
            ]} =
             CliClient.receive_messages(
               "+15555550101",
               executable: executable,
               receive_timeout_s: 2,
               max_messages: 3,
               ignore_attachments: true
             )

    assert File.read!(args_path) |> String.split("\n", trim: true) == [
             "-a",
             "+15555550101",
             "-o",
             "json",
             "receive",
             "--timeout",
             "2",
             "--max-messages",
             "3",
             "--ignore-attachments"
           ]
  end

  test "sends a group message without text or quote author" do
    tmp_dir = System.tmp_dir!()
    args_path = Path.join(tmp_dir, "jido_signal_group_args_#{System.unique_integer([:positive])}")
    executable = Path.join(tmp_dir, "jido_signal_group_#{System.unique_integer([:positive])}.sh")

    File.write!(
      executable,
      "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$SIGNAL_CLI_TEST_ARGS\"\necho ok\n"
    )

    File.chmod!(executable, 0o755)
    previous_args_path = System.get_env("SIGNAL_CLI_TEST_ARGS")
    System.put_env("SIGNAL_CLI_TEST_ARGS", args_path)

    on_exit(fn ->
      File.rm(executable)
      File.rm(args_path)

      if previous_args_path do
        System.put_env("SIGNAL_CLI_TEST_ARGS", previous_args_path)
      else
        System.delete_env("SIGNAL_CLI_TEST_ARGS")
      end
    end)

    assert {:ok, response} =
             CliClient.send_message(nil, "group:group-1", nil,
               executable: executable,
               config_path: "/tmp/signal-config",
               reply_to_id: "10"
             )

    assert is_integer(response["timestamp"])

    assert File.read!(args_path) |> String.split("\n", trim: true) == [
             "-c",
             "/tmp/signal-config",
             "send",
             "-g",
             "group-1"
           ]
  end

  test "reports command exit and executable errors" do
    tmp_dir = System.tmp_dir!()

    executable =
      Path.join(tmp_dir, "jido_signal_failure_#{System.unique_integer([:positive])}.sh")

    File.write!(executable, "#!/bin/sh\necho failed\nexit 7\n")
    File.chmod!(executable, 0o755)
    on_exit(fn -> File.rm(executable) end)

    assert {:error, {:signal_cli_error, 7, "failed"}} =
             CliClient.send_message(nil, "+15555550100", "hello", executable: executable)

    assert {:error, {:signal_cli_error, _}} =
             CliClient.send_message(nil, "+15555550100", "hello", executable: "/does/not/exist/signal-cli")
  end

  test "accepts empty and complete JSON receive output" do
    tmp_dir = System.tmp_dir!()
    empty = Path.join(tmp_dir, "jido_signal_empty_#{System.unique_integer([:positive])}.sh")
    list = Path.join(tmp_dir, "jido_signal_list_#{System.unique_integer([:positive])}.sh")
    lines = Path.join(tmp_dir, "jido_signal_lines_#{System.unique_integer([:positive])}.sh")

    File.write!(empty, "#!/bin/sh\n")
    File.write!(list, "#!/bin/sh\nprintf '%s\\n' '[{\"envelope\":{\"timestamp\":1}}]'\n")

    File.write!(
      lines,
      "#!/bin/sh\nprintf '%s\\n' 'INFO signal-cli' '[{\"envelope\":{\"timestamp\":2}}]'\n"
    )

    for executable <- [empty, list, lines], do: File.chmod!(executable, 0o755)
    on_exit(fn -> Enum.each([empty, list, lines], &File.rm/1) end)

    assert {:ok, []} =
             CliClient.receive_messages(nil, executable: empty, receive_timeout_s: nil)

    assert {:ok, [%{"envelope" => %{"timestamp" => 1}}]} =
             CliClient.receive_messages(nil, executable: list)

    assert {:ok, [%{"envelope" => %{"timestamp" => 2}}]} =
             CliClient.receive_messages(nil, executable: lines)
  end

  test "reports invalid line-delimited JSON" do
    tmp_dir = System.tmp_dir!()

    executable =
      Path.join(tmp_dir, "jido_signal_invalid_#{System.unique_integer([:positive])}.sh")

    File.write!(executable, "#!/bin/sh\nprintf '%s\\n' '{invalid}'\n")
    File.chmod!(executable, 0o755)
    on_exit(fn -> File.rm(executable) end)

    assert {:error, {:invalid_receive_output, %Jason.DecodeError{}, "{invalid}"}} =
             CliClient.receive_messages(nil, executable: executable)
  end
end
