defmodule Jido.Chat.StreamMarkdownFixtures do
  @moduledoc false

  @doc "Returns Markdown documents that cover supported stream boundaries."
  @spec supported_documents() :: [{atom(), String.t()}]
  def supported_documents do
    [
      {:split_emphasis, "Before **bold _and italic_** after"},
      {:split_link, "Read [the guide](https://jido.run/docs?q=chat) now."},
      {:list, "Plan:\n\n- first\n- second\n\nDone."},
      {:code_fence, "```elixir\nIO.puts(\"hello\")\n```\n\nDone."},
      {:structural_whitespace, "Heading\n\nParagraph  \nnext line\n\n"},
      {:empty_table_cells, "| Name |  | State |\n| --- | --- | --- |\n| alpha |  | ready |\n|  | beta |  |"}
    ]
  end

  @doc "Splits text into one-character stream chunks."
  @spec one_character_chunks(String.t()) :: [String.t()]
  def one_character_chunks(text), do: String.codepoints(text)
end
