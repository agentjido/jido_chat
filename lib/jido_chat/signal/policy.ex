defmodule Jido.Chat.Signal.Policy do
  @moduledoc false

  alias Jido.Chat.Errors.Contract
  alias Jido.Signal.{Context, Serialization, Trace}

  @context_fields ~w(traceparent tracestate causationid)
  @signal_bytes 262_144
  @private_keys ~w(raw credentials token access_token refresh_token password secret client pid qr pairing_code)

  @doc false
  @spec error(atom(), atom() | nil) :: {:error, Contract.t()}
  def error(code, field \\ nil), do: {:error, Contract.exception(code: code, field: field)}

  @doc false
  @spec constructor_options(term()) :: :ok | {:error, Contract.t()}
  def constructor_options(opts) do
    cond do
      is_list(opts) and Keyword.keyword?(opts) and length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) ->
        option_keys(Keyword.keys(opts))

      is_map(opts) and not is_struct(opts) ->
        option_keys(Map.keys(opts))

      true ->
        error(:invalid_options)
    end
  end

  defp option_keys(keys) do
    normalized = Enum.map(keys, &to_string/1)
    allowed = ~w(id source subject time extensions datacontenttype)

    if length(Enum.uniq(normalized)) == length(normalized) and normalized -- allowed == [],
      do: :ok,
      else: error(:invalid_options)
  rescue
    _ -> error(:invalid_options)
  end

  @doc false
  @spec validate_json(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_json(value, _opts) do
    if json_value?(value, 0), do: :ok, else: {:error, "Signal data must contain safe string-key JSON values"}
  end

  defp json_value?(_value, depth) when depth > 32, do: false
  defp json_value?(value, _depth) when is_nil(value) or is_boolean(value) or is_number(value), do: true
  defp json_value?(value, _depth) when is_binary(value), do: String.valid?(value)
  defp json_value?(value, depth) when is_list(value), do: Enum.all?(value, &json_value?(&1, depth + 1))

  defp json_value?(value, depth) when is_map(value) and not is_struct(value) do
    Enum.all?(value, fn {key, item} ->
      is_binary(key) and String.valid?(key) and key not in @private_keys and json_value?(item, depth + 1)
    end)
  end

  defp json_value?(_value, _depth), do: false

  @doc false
  @spec validate(Jido.Signal.t()) :: {:ok, Jido.Signal.t()} | {:error, Contract.t()}
  def validate(%Jido.Signal{} = signal) do
    with true <- is_binary(signal.id) and byte_size(signal.id) in 1..128,
         :ok <- context(signal),
         :ok <- encoded_size(signal) do
      {:ok, signal}
    else
      false -> error(:invalid_request, :id)
      error -> error
    end
  end

  defp context(signal) do
    attrs = signal.extensions

    valid =
      is_map(attrs) and Map.keys(attrs) -- @context_fields == [] and
        Enum.all?(attrs, fn {_name, value} -> is_binary(value) and String.valid?(value) end) and
        valid_trace?(attrs) and valid_causation?(Context.get(signal, "causationid")) and
        valid_source?(signal.source)

    if valid, do: :ok, else: error(:invalid_context)
  end

  defp valid_source?(source) when is_binary(source) do
    case URI.parse(source) do
      %URI{userinfo: nil} -> true
      _ -> false
    end
  end

  defp valid_source?(_), do: false

  defp valid_trace?(attrs) do
    traceparent = attrs["traceparent"]
    tracestate = attrs["tracestate"]

    case traceparent do
      nil ->
        is_nil(tracestate)

      value ->
        match?({:ok, _}, Trace.from_traceparent(value, tracestate)) and
          (is_nil(tracestate) or Trace.validate_tracestate(tracestate, []) == :ok)
    end
  end

  defp valid_causation?(nil), do: true
  defp valid_causation?(id), do: is_binary(id) and byte_size(id) in 1..128

  defp encoded_size(signal) do
    case Serialization.serialize(signal) do
      {:ok, encoded} when byte_size(encoded) <= @signal_bytes -> :ok
      {:ok, _encoded} -> error(:signal_too_large)
      {:error, _} -> error(:unsafe_data)
    end
  end
end
