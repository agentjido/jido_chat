defmodule Jido.Chat.Errors do
  @moduledoc """
  Splode error aggregator for Jido.Chat.
  """

  use Splode,
    error_classes: [
      ingress: Jido.Chat.Errors.Ingress,
      validation: Jido.Chat.Errors.Validation
    ],
    unknown_error: Jido.Chat.Errors.Unknown
end
