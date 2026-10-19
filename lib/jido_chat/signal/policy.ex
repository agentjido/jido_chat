defmodule Jido.Chat.Signal.Policy do
  @moduledoc """
  Chat construction and admission rules for native `Jido.Signal` definitions.

  Define data with `use Jido.Signal`. Use `new/3` when construction must also
  enforce Chat data, context, and size rules. Native definition constructors
  retain their native behavior. Every Chat admission boundary uses `validate/2`.

  Traces use `Jido.Signal.Trace` and the current Jido tracing context. Replies
  retain the parent trace and use Jido's `jidocausationid` context attribute.
  The host owns span lifetime, sampling, and export.
  """

  alias Jido.Chat.Errors.Contract
  alias Jido.Signal.{Catalog, Context, Trace}
  alias Jido.Tracing.Context, as: TraceContext
  alias Jido.Tracing.Trace, as: JidoTrace

  @context_fields ~w(traceparent tracestate jidocausationid)
  @signal_bytes 262_144
  @private_keys ~w(raw credentials token access_token refresh_token password secret client pid qr pairing_code)

  @doc false
  @spec error(atom()) :: {:error, Contract.t()}
  def error(code), do: error(code, nil)

  @doc false
  @spec error(atom(), atom() | nil) :: {:error, Contract.t()}
  def error(code, field), do: {:error, Contract.exception(code: code, field: field)}

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
  def validate(signal) do
    with :ok <- fields(signal),
         :ok <- encoded_size(signal) do
      {:ok, signal}
    end
  end

  defp fields(%Jido.Signal{} = signal) do
    with true <- is_binary(signal.id) and byte_size(signal.id) in 1..128,
         :ok <- safe_data(signal.data),
         :ok <- context(signal) do
      :ok
    else
      false -> error(:invalid_request, :id)
      error -> error
    end
  end

  defp fields(_signal), do: error(:invalid_request)

  defp safe_data(data) do
    case validate_json(data, []) do
      :ok -> :ok
      {:error, _} -> error(:unsafe_data)
    end
  end

  defp context(signal) do
    attrs = signal.extensions

    valid =
      is_map(attrs) and Map.keys(attrs) -- @context_fields == [] and
        Enum.all?(attrs, fn {_name, value} -> is_binary(value) and String.valid?(value) end) and
        valid_trace?(attrs) and valid_causation?(Context.get(signal, "jidocausationid")) and
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
    wire = Jido.Signal.to_map(signal)

    with true <- json_value?(Map.delete(wire, "data"), 0),
         {:ok, encoded} <- Jason.encode_to_iodata(wire) do
      if IO.iodata_length(encoded) <= @signal_bytes, do: :ok, else: error(:signal_too_large)
    else
      _ -> error(:unsafe_data)
    end
  rescue
    _ -> error(:unsafe_data)
  end

  @doc "Constructs a native Signal with Chat validation and trace context."
  @spec new(module(), term(), keyword() | map()) :: {:ok, Jido.Signal.t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def new(definition, data, opts \\ []) do
    construct(data, opts, fn -> definition.new(data, opts) end)
  end

  @doc "Constructs a Chat Signal or raises a contract error."
  @spec new!(module(), term(), keyword() | map()) :: Jido.Signal.t() | no_return()
  def new!(definition, data, opts \\ []) do
    case new(definition, data, opts) do
      {:ok, signal} -> signal
      {:error, error} -> raise error
    end
  end

  @doc "Constructs a reply with its parent's native trace and causation context."
  @spec reply(module(), term(), Jido.Signal.t(), keyword() | map()) ::
          {:ok, Jido.Signal.t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def reply(definition, data, parent, opts \\ []) do
    construct(data, opts, fn ->
      with {:ok, parent} <- prepare(parent),
           {:ok, signal} <- definition.new(data, opts) do
        JidoTrace.put(signal, Map.put(JidoTrace.get(parent), :causation_id, parent.id))
      end
    end)
  end

  @doc "Validates a native Signal against its exact catalog definition and Chat policy."
  @spec validate(Catalog.t(), term()) :: {:ok, Jido.Signal.t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def validate(catalog, signal) do
    with {:ok, signal} <- validate(signal),
         {:ok, validated} <- Catalog.validate(catalog, signal) do
      if validated === signal, do: {:ok, validated}, else: validate(validated)
    else
      {:error, %Contract{}} = error -> error
      {:error, _} -> error(:invalid_request, :data)
    end
  end

  defp construct(data, opts, build) do
    with :ok <- constructor_options(opts),
         :ok <- safe_data(data),
         {:ok, signal} <- build.() do
      prepare(signal)
    else
      {:error, %Jido.Chat.Errors.Contract{}} = error -> error
      {:error, _} -> error(:invalid_request, :data)
    end
  end

  @doc false
  @spec prepare(term()) :: {:ok, Jido.Signal.t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def prepare(signal) do
    with :ok <- fields(signal),
         {:ok, signal} <- ensure_trace(signal),
         :ok <- context(signal),
         :ok <- encoded_size(signal) do
      {:ok, signal}
    else
      {:error, %Jido.Chat.Errors.Contract{}} = error -> error
      {:error, _} -> error(:invalid_context)
    end
  end

  defp ensure_trace(signal) do
    case {Trace.get(signal), TraceContext.get()} do
      {nil, context} when is_map(context) ->
        cause = Jido.Signal.get_context(signal, "jidocausationid")
        JidoTrace.put(signal, Map.put(context, :causation_id, cause))

      _ ->
        with {:ok, traced, _trace} <- Trace.ensure(signal), do: {:ok, traced}
    end
  end
end
