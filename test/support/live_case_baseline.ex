defmodule Jido.Chat.LiveCase.Baseline do
  @moduledoc false

  alias Jido.Chat.LiveCase

  @cases [
    {"P01", "portable text completion"},
    {"P02", "rich reply and controls"},
    {"P03", "HTML text"},
    {"P04", "lazy stream and plain previews"},
    {"P05", "rich draft preview and final text"},
    {"P06", "send-and-edit stream"},
    {"P07", "stream coalescing and final flush"},
    {"P08", "inline file and download"},
    {"P09", "local upload and reference reuse"},
    {"P10", "image delivery and normalized media"},
    {"P11", "capability discovery"},
    {"P12", "edit and clear controls"},
    {"P13", "delete and repeat delete"},
    {"P14", "add and remove reactions"},
    {"P15", "room metadata and trace"},
    {"P16", "typing acknowledgment"},
    {"P17", "thread creation and routing"},
    {"P18", "thread rejection"},
    {"P19", "invalid public input"},
    {"P20", "real send rejection"},
    {"P21", "receive and normalize messages"},
    {"A01", "native send, edit, and delete"},
    {"A02", "metadata, typing, direct addressing and bot identity"},
    {"A03", "read webhook status"},
    {"A04", "public text and file byte round trip"},
    {"A05", "rich draft stream"},
    {"A06", "explicit send-and-edit stream"},
    {"A07", "finite render and final send"},
    {"A08", "explicit drafts in a Flow"},
    {"A09", "rich send, reply, edit and finite render"},
    {"A10", "actual reply metadata"},
    {"A11", "native reaction Actions"},
    {"A12", "document metadata and exact JSON bytes"},
    {"A13", "media delivery and normalization"},
    {"A14", "native local file source"},
    {"A15", "poll through Router and Dispatch"},
    {"A16", "native thread or topic routing"},
    {"A17", "fresh interactive callback and answer"}
  ]

  def ids, do: Enum.map(@cases, &elem(&1, 0))

  def register(cases, unavailable \\ %{}, group \\ :api) do
    providers = Map.new(cases, &{&1.id, &1})
    supplied = Enum.map(cases, & &1.id) ++ Map.keys(unavailable)

    if Enum.sort(supplied) != Enum.sort(ids()) do
      raise ArgumentError, "declare each baseline case once with a test body or an unsupported reason"
    end

    Enum.map(@cases, fn {id, name} ->
      case Map.fetch(providers, id) do
        {:ok, spec} -> spec
        :error -> LiveCase.spec(group, id, name, nil, unsupported: Map.fetch!(unavailable, id))
      end
    end)
  end
end
