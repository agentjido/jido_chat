defmodule Jido.Chat.ArchitectureTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../lib/jido_chat", __DIR__)
  @integration_roots ["plugin", "sensor"]

  test "Core does not reference Integration or Runtime modules" do
    forbidden = [Jido.Chat.Plugin, Jido.Chat.Sensor, Jido.Chat.Runtime]

    for file <- core_files(), module <- module_references(file) do
      refute Enum.any?(forbidden, &same_or_child?(module, &1)),
             "#{relative(file)} references #{inspect(module)}"
    end
  end

  test "Integration does not reference Runtime modules" do
    for file <- integration_files(), module <- module_references(file) do
      refute same_or_child?(module, Jido.Chat.Runtime),
             "#{relative(file)} references #{inspect(module)}"
    end
  end

  test "Providers do not reference Runtime modules" do
    for file <- provider_files(), module <- module_references(file) do
      refute same_or_child?(module, Jido.Chat.Runtime),
             "#{relative(file)} references #{inspect(module)}"
    end
  end

  test "Core has no built-in provider dependency" do
    # Core shares the Jido.Chat.Signal namespace with the Signal Messenger
    # facade. Restrict the check to concrete provider module references.
    provider_modules = for file <- provider_files(), module <- module_definitions(file), into: MapSet.new(), do: module
    provider_modules = MapSet.delete(provider_modules, Jido.Chat.Signal)

    for file <- [Path.join(@root, "../jido_chat.ex") | core_files()], module <- module_references(file) do
      refute MapSet.member?(provider_modules, module),
             "#{relative(file)} references #{inspect(module)}"
    end
  end

  defp provider_files, do: Path.wildcard(Path.join(@root, "providers/**/*.ex"))

  defp core_files do
    @root
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.reject(fn file ->
      relative = Path.relative_to(file, @root)
      Enum.any?(@integration_roots ++ ["runtime", "providers"], &path_root?(relative, &1))
    end)
  end

  defp integration_files do
    Enum.flat_map(@integration_roots, fn root ->
      [Path.join(@root, "#{root}.ex") | Path.wildcard(Path.join(@root, "#{root}/**/*.ex"))]
    end)
  end

  defp module_references(file) do
    modules_in(file, fn
      {:__aliases__, _, parts} -> parts
      _ -> nil
    end)
  end

  defp module_definitions(file) do
    modules_in(file, fn
      {:defmodule, _, [{:__aliases__, _, parts}, _]} -> parts
      _ -> nil
    end)
  end

  defp modules_in(file, select_parts) do
    file
    |> File.read!()
    |> Code.string_to_quoted!()
    |> Macro.prewalk([], fn node, modules ->
      case select_parts.(node) do
        nil -> {node, modules}
        parts -> {node, [Module.concat(parts) | modules]}
      end
    end)
    |> elem(1)
    |> Enum.uniq()
  end

  defp same_or_child?(module, root) do
    module_parts = Module.split(module)
    root_parts = Module.split(root)
    Enum.take(module_parts, length(root_parts)) == root_parts
  end

  defp path_root?(relative, root),
    do: relative == "#{root}.ex" or String.starts_with?(relative, "#{root}/")

  defp relative(file), do: Path.relative_to(file, Path.expand("../..", __DIR__))
end
