defmodule Jido.Chat.Signal.Definition do
  @moduledoc """
  Defines a strict chat Signal. Provider incoming facts use `kind: :fact` and an
  explicit `owner`. Declare these definitions in the adapter's `event_definitions/0`.
  Facts require `item_id` and `delivery_id`; room facts also use `room_id` and the
  client-scoped conversation subject. Data and trace context follow Chat policy.

  Each module still constructs a native `Jido.Signal`. This macro adds the Chat
  data, context, size, and trace rules at construction. `Jido.Signal` owns the
  envelope, schema identity, validation, and catalog protocol.
  """

  @doc "Defines a typed chat fact, request, or result with JSON and context checks."
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    kind = Keyword.fetch!(opts, :kind)
    owner = Keyword.fetch!(opts, :owner)
    signal_opts = Keyword.drop(opts, [:kind, :owner])
    schema = Keyword.fetch!(signal_opts, :schema)

    signal_opts =
      Keyword.put(
        signal_opts,
        :schema,
        quote do
          unquote(schema) |> Zoi.refine({Jido.Chat.Signal.Policy, :validate_json, []})
        end
      )

    quote do
      use Jido.Signal, unquote(signal_opts)
      @doc false
      def __signal_kind__, do: unquote(kind)
      @doc false
      def __signal_owner__, do: unquote(owner)
      defoverridable new: 2, new!: 2

      @spec new(term(), keyword() | map()) ::
              {:ok, Jido.Signal.t()} | {:error, Jido.Chat.Errors.Contract.t()}
      def new(data, opts) do
        with :ok <- Jido.Chat.Signal.Policy.constructor_options(opts),
             {:ok, signal} <- super(data, opts),
             {:ok, signal} <- Jido.Chat.Signal.Policy.validate(signal),
             {:ok, signal, _trace} <- Jido.Signal.Trace.ensure(signal),
             {:ok, signal} <- Jido.Chat.Signal.Policy.validate(signal) do
          {:ok, signal}
        else
          {:error, %Jido.Chat.Errors.Contract{}} = error -> error
          {:error, _reason} -> Jido.Chat.Signal.Policy.error(:invalid_request, :data)
        end
      end

      @spec new!(term(), keyword() | map()) :: Jido.Signal.t() | no_return()
      def new!(data, opts) do
        case new(data, opts) do
          {:ok, signal} -> signal
          {:error, error} -> raise error
        end
      end
    end
  end
end
