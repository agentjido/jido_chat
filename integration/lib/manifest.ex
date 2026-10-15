defmodule Jido.Chat.Integration.Manifest do
  @moduledoc false

  @operations ~w(send_message send_file post_message edit_message delete_message start_typing fetch_metadata fetch_thread fetch_message get_user fetch_subject get_thread_participants mark_as_read fetch_media add_reaction remove_reaction post_ephemeral post_channel_message stream open_modal load_options fetch_messages fetch_channel_messages list_threads open_thread open_dm)
  @adapters ~w(jido_chat_telegram jido_chat_slack jido_chat_discord jido_chat_github jido_chat_signal jido_chat_teams jido_chat_whatsapp jido_chat_x)
  @files ~w(api-map catalog operations adapter-matrix version-matrix protocol gate-status)

  def verify(directory, phase) do
    {manifests, errors} = read_manifests(directory)
    errors = errors ++ contract_errors(manifests)

    errors =
      if phase == "all" do
        errors ++ conformance_errors()
      else
        errors
      end

    %{phase: phase, state: if(errors == [], do: "pass", else: "fail"), errors: errors}
  end

  defp read_manifests(directory) do
    Enum.reduce(@files, {%{}, []}, fn name, {manifests, errors} ->
      path = Path.join(directory, name <> ".json")

      with {:ok, data} <- File.read(path), {:ok, value} <- Jason.decode(data) do
        {Map.put(manifests, name, value), errors}
      else
        _ -> {manifests, errors ++ ["Missing or invalid manifest: #{name}.json"]}
      end
    end)
  end

  def contract_errors(manifests) do
    []
    |> check_operations(manifests["operations"])
    |> check_adapters(manifests["adapter-matrix"])
    |> check_catalog(manifests["catalog"])
    |> check_api(manifests["api-map"])
    |> check_protocol(manifests["protocol"])
    |> check_versions(manifests["version-matrix"])
  end

  defp check_operations(errors, %{"operations" => rows, "state" => "frozen"}) do
    actual = Enum.map(rows, & &1["operation"])

    errors =
      if Enum.sort(actual) == Enum.sort(@operations),
        do: errors,
        else: errors ++ ["All 26 operation rows must occur once."]

    Enum.reduce(rows, errors, fn row, errors ->
      valid =
        row["callback"]["name"] == row["operation"] and
          is_integer(row["callback"]["arity"]) and row["callback"]["arity"] in 2..4 and
          row["capability"] == row["operation"] and row["result_variant"] == row["operation"] and
          row["result_module"] == "Jido.Chat.Signal.OperationCompleted" and
          row["failure_module"] == "Jido.Chat.Signal.OperationFailed" and
          is_map(row["request_schema"]) and is_map(row["result_schema"]) and
          is_binary(row["resource_rule"])

      if valid, do: errors, else: errors ++ ["Incomplete operation: #{row["operation"]}"]
    end)
  end

  defp check_operations(errors, _), do: errors ++ ["The operation inventory is not frozen."]

  defp check_adapters(errors, %{"adapters" => rows, "state" => "frozen"}) do
    actual = Enum.map(rows, & &1["package"])

    errors =
      if Enum.sort(actual) == Enum.sort(@adapters),
        do: errors,
        else: errors ++ ["All eight adapter rows must occur once."]

    Enum.reduce(rows, errors, fn row, errors ->
      valid =
        Enum.sort(Map.keys(row["operation_support"] || %{})) == Enum.sort(@operations) and
          Enum.all?(
            Map.values(row["operation_support"] || %{}),
            &(&1 in ["native", "fallback", "unsupported"])
          ) and
          is_map(row["event_support"]) and map_size(row["event_support"]) > 0 and
          Enum.all?(Map.values(row["event_support"]), &(&1 in ["native", "unsupported"])) and
          row["membership_support"] in ["native", "unsupported"] and
          row["participant_query_support"] in ["native", "fallback", "unsupported"] and
          row["participant_query_complete"] == false and is_map(row["transport"]) and
          Enum.all?(
            ~w(delivery_identity item_identity acceptance acknowledgement retry_unit),
            &is_binary(row["transport"][&1])
          )

      if valid do
        errors
      else
        errors ++ ["Incomplete operation support: #{row["package"]}"]
      end
    end)
  end

  defp check_adapters(errors, _), do: errors ++ ["The adapter inventory is not frozen."]

  defp check_catalog(errors, %{"definitions" => rows, "state" => "frozen"}) when rows != [] do
    pairs = Enum.map(rows, &{&1["type"], &1["dataschema"]})

    errors =
      if length(Enum.uniq(pairs)) == length(pairs),
        do: errors,
        else: errors ++ ["Duplicate catalog type/schema pair."]

    Enum.reduce(rows, errors, fn row, errors ->
      owner = row["owner"]
      namespace = if owner == "chat", do: "jido.chat.", else: "jido.messaging."

      module_namespace =
        if owner == "chat", do: "Jido.Chat.Signal.", else: "Jido.Messaging.Signal."

      valid =
        owner in ["chat", "messaging"] and is_map(row["fixture"]) and
          is_map(row["data_schema"]) and is_binary(row["source_rule"]) and
          is_binary(row["subject_rule"]) and String.starts_with?(row["type"] || "", namespace) and
          String.starts_with?(row["module"] || "", module_namespace) and
          row["kind"] in ["fact", "command", "query", "result"] and
          Enum.sort(row["allowed_context_fields"] || []) == ~w(causationid traceparent tracestate) and
          valid_schema?(row["data_schema"]) and valid_fixture?(row)

      if valid, do: errors, else: errors ++ ["Incomplete catalog definition: #{row["module"]}"]
    end)
  end

  defp check_catalog(errors, _), do: errors ++ ["The catalog is not frozen."]

  defp check_api(errors, %{"exports" => rows, "state" => "frozen"}) when rows != [] do
    errors =
      if length(
           Enum.uniq_by(
             rows,
             &{&1["package"], &1["module"], &1["function"], &1["arity"], &1["generated_template"]}
           )
         ) == length(rows), do: errors, else: errors ++ ["Duplicate API export mapping."]

    Enum.reduce(rows, errors, fn row, errors ->
      if row["classification"] in [
           "request-result",
           "retained-domain-value",
           "private-provider-operation",
           "private-implementation",
           "transport-control",
           "signal-handler"
         ] and is_binary(row["replacement"]) and row["replacement"] != "" and
           is_binary(row["reason"]) do
        errors
      else
        errors ++ ["Unclassified API: #{row["module"]}.#{row["function"]}/#{row["arity"]}"]
      end
    end)
  end

  defp check_api(errors, _), do: errors ++ ["The API map is not frozen."]

  defp check_protocol(errors, %{"protocol_version" => 1, "state" => "frozen", "limits" => limits}) do
    expected = %{
      "signal_bytes" => 262_144,
      "delivery_bytes" => 1_048_576,
      "signals_per_delivery" => 100,
      "item_failures_per_delivery" => 20
    }

    if limits == expected, do: errors, else: errors ++ ["The agreed safety limits changed."]
  end

  defp check_protocol(errors, _), do: errors ++ ["The protocol contract is not frozen."]

  defp check_versions(errors, %{"packages" => rows, "upstream_graph" => graph}) do
    errors =
      if Enum.all?(~w(jido_signal jido jido_action zoi jido_ai), fn key ->
           is_map(graph[key]) and is_binary(graph[key]["ref"]) and
             byte_size(graph[key]["ref"]) == 40
         end), do: errors, else: errors ++ ["Missing immutable v3 source refs."]

    Enum.reduce(Enum.filter(rows, &Map.has_key?(&1, "base_sha")), errors, fn row, errors ->
      valid =
        is_binary(row["base_sha"]) and byte_size(row["base_sha"]) == 40 and
          is_binary(row["intended_version"]) and is_map(row["publication_history"]) and
          is_binary(row["rollback_pin"])

      if valid, do: errors, else: errors ++ ["Incomplete version row: #{row["package"]}"]
    end)
  end

  defp check_versions(errors, _), do: errors ++ ["The version matrix is incomplete."]

  defp valid_fixture?(row) do
    fixture = row["fixture"]

    with {:ok, ^fixture} <- Zoi.parse(Zoi.from_json_schema(row["data_schema"]), fixture),
         ^fixture <- Jason.decode!(Jason.encode!(fixture)),
         {:ok, _signal} <-
           Jido.Signal.new(
             row["type"],
             fixture,
             Map.put(row["fixture_options"], "dataschema", row["dataschema"])
           ) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp valid_schema?(%{"oneOf" => rows}), do: rows != [] and Enum.all?(rows, &valid_schema?/1)
  defp valid_schema?(%{"anyOf" => rows}), do: rows != [] and Enum.all?(rows, &valid_schema?/1)
  defp valid_schema?(%{"enum" => values}), do: values != [] and Enum.all?(values, &is_binary/1)

  defp valid_schema?(
         %{"type" => "object", "properties" => fields, "additionalProperties" => false} = schema
       ) do
    Enum.all?(fields, fn {key, value} ->
      is_binary(key) and key not in ~w(raw token credentials client pid) and valid_schema?(value)
    end) and
      Enum.all?(schema["required"] || [], &Map.has_key?(fields, &1))
  end

  defp valid_schema?(%{"type" => "object", "additionalProperties" => value}) when is_map(value),
    do: valid_schema?(value)

  defp valid_schema?(%{"type" => "array", "items" => value}), do: valid_schema?(value)

  defp valid_schema?(%{"type" => ["string", "null"]} = schema),
    do: not Map.has_key?(schema, "format")

  defp valid_schema?(%{"type" => type} = schema)
       when type in ["string", "integer", "number", "boolean", "null"],
       do: not Map.has_key?(schema, "format")

  defp valid_schema?(_), do: false

  defp conformance_errors do
    if Code.ensure_loaded?(Jido.Chat.Integration.Conformance) and
         function_exported?(Jido.Chat.Integration.Conformance, :run, 0) do
      case apply(Jido.Chat.Integration.Conformance, :run, []) do
        %{state: "pass", assertions: assertions} when map_size(assertions) == 14 -> []
        _ -> ["C01–C14 conformance did not pass."]
      end
    else
      ["The C01–C14 conformance runner is pending. All gates cannot pass."]
    end
  end
end
