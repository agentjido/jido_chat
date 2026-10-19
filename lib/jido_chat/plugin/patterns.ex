defmodule Jido.Chat.Plugin.Patterns do
  @moduledoc false

  @doc false
  @spec selected?(String.t(), String.t() | [String.t()]) :: boolean()
  def selected?(type, patterns),
    do: Enum.any?(List.wrap(patterns), &Jido.Signal.Router.matches?(type, &1))

  @doc false
  @spec valid?(term(), [String.t()]) :: boolean()
  def valid?(patterns, types) do
    patterns = List.wrap(patterns)

    patterns != [] and
      Enum.all?(patterns, fn pattern ->
        is_binary(pattern) and Jido.Signal.Router.Route.validate_path(pattern, []) == :ok and
          Enum.any?(types, &Jido.Signal.Router.matches?(&1, pattern))
      end)
  end

  # Intersect the route languages, restricted to Chat. Each ** has an empty
  # transition and a consuming loop. Visited states bound the search.
  @doc false
  @spec overlap?(String.t(), String.t()) :: boolean()
  def overlap?(left, right),
    do: search([{String.split(left, "."), String.split(right, "."), ["jido", "chat", "**"]}], %{})

  defp search([], _seen), do: false

  defp search([state | rest], seen) do
    cond do
      state == {[], [], []} -> true
      Map.has_key?(seen, state) -> search(rest, seen)
      true -> search(transitions(state) ++ rest, Map.put(seen, state, true))
    end
  end

  defp transitions({a, b, c} = state) do
    empty =
      for {segments, index} <- Enum.with_index([a, b, c]),
          match?(["**" | _], segments),
          do: put_elem(state, index, tl(segments))

    consume =
      if a != [] and b != [] and c != [] and compatible?([hd(a), hd(b), hd(c)]),
        do: [{advance(a), advance(b), advance(c)}],
        else: []

    empty ++ consume
  end

  defp compatible?(segments), do: segments |> Enum.reject(&(&1 in ["*", "**"])) |> Enum.uniq() |> length() <= 1
  defp advance(["**" | _] = segments), do: segments
  defp advance([_ | tail]), do: tail
end
