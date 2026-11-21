defmodule Jido.Chat.Signal.Transport.CliClient do
  @moduledoc "One-shot `signal-cli` transport for local live tests and simple deployments."
  @behaviour Jido.Chat.Signal.Transport

  alias Jido.Chat.Signal.AttachmentRef

  @impl true
  def send_message(account, target, text, opts) do
    executable =
      Keyword.get(opts, :executable) || System.get_env("SIGNAL_CLI_PATH") || "signal-cli"

    with {:ok, send_args} <- send_args(target, text, opts),
         {:ok, output} <- run(executable, account_args(account, opts) ++ send_args) do
      {:ok,
       %{
         "timestamp" => timestamp_from_output(output) || System.system_time(:millisecond),
         "target" => to_string(target),
         "output" => output
       }}
    end
  end

  @doc """
  Receives pending Signal envelopes using `signal-cli receive`.

  `signal-cli` returns JSON when the global `-o json` flag is supplied. Different
  versions may emit either a JSON list or line-delimited JSON objects, so parsing
  accepts both formats.
  """
  @spec receive_messages(String.t() | nil, keyword()) :: {:ok, [map()]} | {:error, term()}
  @impl true
  def receive_messages(account, opts \\ []) do
    executable =
      Keyword.get(opts, :executable) || System.get_env("SIGNAL_CLI_PATH") || "signal-cli"

    args = account_args(account, opts) ++ ["-o", "json", "receive"] ++ receive_args(opts)

    with {:ok, output} <- run(executable, args) do
      decode_receive_output(output)
    end
  end

  defp account_args(account, opts) do
    config_path = Keyword.get(opts, :config_path) || Keyword.get(opts, :config)

    []
    |> maybe_global_arg("-c", config_path)
    |> maybe_global_arg("-a", account)
  end

  defp maybe_global_arg(args, _flag, value) when value in [nil, ""], do: args
  defp maybe_global_arg(args, flag, value), do: args ++ [flag, to_string(value)]

  defp receive_args(opts) do
    []
    |> maybe_timeout_arg(opts)
    |> maybe_max_messages_arg(opts)
    |> maybe_flag(opts, :ignore_attachments, "--ignore-attachments")
    |> maybe_flag(opts, :ignore_stories, "--ignore-stories")
    |> maybe_flag(opts, :ignore_avatars, "--ignore-avatars")
    |> maybe_flag(opts, :ignore_stickers, "--ignore-stickers")
    |> maybe_flag(opts, :send_read_receipts, "--send-read-receipts")
  end

  defp maybe_timeout_arg(args, opts) do
    case Keyword.get(opts, :receive_timeout_s, Keyword.get(opts, :timeout_s, 1)) do
      nil -> args
      timeout -> args ++ ["--timeout", to_string(timeout)]
    end
  end

  defp maybe_max_messages_arg(args, opts) do
    case Keyword.get(opts, :max_messages) do
      nil -> args
      max_messages -> args ++ ["--max-messages", to_string(max_messages)]
    end
  end

  defp maybe_flag(args, opts, key, flag) do
    if Keyword.get(opts, key, false), do: args ++ [flag], else: args
  end

  defp send_args(target, text, opts) do
    target = to_string(target)

    with {:ok, attachments} <- attachment_args(opts) do
      {:ok,
       ["send"] ++
         recipient_args(target) ++
         attachments ++
         quote_args(target, opts) ++
         message_args(text) ++
         trailing_recipient_args(target)}
    end
  end

  defp recipient_args("group:" <> group_id), do: ["-g", group_id]
  defp recipient_args(_target), do: []

  defp trailing_recipient_args("group:" <> _group_id), do: []
  defp trailing_recipient_args(target), do: [target]

  defp attachment_args(opts) do
    opts
    |> Keyword.get(:attachments, [])
    |> AttachmentRef.refs()
    |> case do
      {:ok, []} -> {:ok, []}
      {:ok, refs} -> {:ok, ["-a" | refs]}
      {:error, _reason} = error -> error
    end
  end

  defp quote_args(target, opts) do
    timestamp = Keyword.get(opts, :quote_timestamp) || Keyword.get(opts, :reply_to_id)

    author =
      Keyword.get(opts, :quote_author) || Keyword.get(opts, :reply_author) || quote_author(target)

    message = Keyword.get(opts, :quote_message)

    cond do
      timestamp in [nil, ""] or author in [nil, ""] ->
        []

      message in [nil, ""] ->
        ["--quote-timestamp", to_string(timestamp), "--quote-author", to_string(author)]

      true ->
        [
          "--quote-timestamp",
          to_string(timestamp),
          "--quote-author",
          to_string(author),
          "--quote-message",
          to_string(message)
        ]
    end
  end

  defp message_args(text) when text in [nil, ""], do: []
  defp message_args(text), do: ["-m", text]

  defp quote_author("group:" <> _group_id), do: nil
  defp quote_author(target), do: target

  defp run(executable, args) do
    case System.cmd(executable, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, status} -> {:error, {:signal_cli_error, status, String.trim(output)}}
    end
  rescue
    exception in ErlangError -> {:error, {:signal_cli_error, exception.original}}
  end

  defp timestamp_from_output(output) when is_binary(output) do
    case Regex.run(~r/\b\d{10,}\b/, output) do
      [timestamp | _] -> timestamp
      _ -> nil
    end
  end

  defp decode_receive_output(""), do: {:ok, []}

  defp decode_receive_output(output) when is_binary(output) do
    output
    |> Jason.decode()
    |> case do
      {:ok, decoded} ->
        {:ok, normalize_decoded_messages(decoded)}

      {:error, _reason} ->
        decode_json_lines(output)
    end
  end

  defp decode_json_lines(output) do
    result =
      output
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&json_candidate?/1)
      |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
        case Jason.decode(line) do
          {:ok, decoded} ->
            items = normalize_decoded_messages(decoded)
            {:cont, {:ok, Enum.reverse(items, acc)}}

          {:error, reason} ->
            {:halt, {:error, {:invalid_receive_output, reason, line}}}
        end
      end)

    case result do
      {:ok, messages} -> {:ok, Enum.reverse(messages)}
      error -> error
    end
  end

  defp json_candidate?(""), do: false
  defp json_candidate?("{" <> _rest), do: true
  defp json_candidate?("[" <> _rest), do: true
  defp json_candidate?(_line), do: false

  defp normalize_decoded_messages(messages) when is_list(messages), do: messages
  defp normalize_decoded_messages(message), do: [message]
end
