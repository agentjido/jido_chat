defmodule Jido.Chat.Slack.Transport do
  @moduledoc "Transport contract for Slack Web API operations."

  @type token :: String.t()
  @type id :: String.t()
  @type api_result :: {:ok, map() | boolean() | String.t()} | {:error, term()}

  @callback send_message(token(), id(), String.t(), keyword()) :: api_result()
  @callback send_file(token(), id(), map(), keyword()) :: api_result()
  @callback edit_message(token(), id(), id(), String.t(), keyword()) :: api_result()
  @callback delete_message(token(), id(), id(), keyword()) :: api_result()
  @callback fetch_metadata(token(), id(), keyword()) :: api_result()
  @callback fetch_thread(token(), id(), id(), keyword()) :: api_result()
  @callback fetch_message(token(), id(), id(), keyword()) :: api_result()
  @callback get_user(token(), id(), keyword()) :: api_result()
  @callback mark_as_read(token(), id(), id(), keyword()) :: api_result()
  @callback download_file(token(), String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  @callback fetch_messages(token(), id(), keyword()) :: api_result()
  @callback list_threads(token(), id(), keyword()) :: api_result()
  @callback add_reaction(token(), id(), id(), String.t(), keyword()) :: api_result()
  @callback remove_reaction(token(), id(), id(), String.t(), keyword()) :: api_result()
  @callback post_ephemeral(token(), id(), id(), String.t(), keyword()) :: api_result()
  @callback open_dm(token(), id(), keyword()) :: api_result()
  @callback open_modal(token(), String.t(), map(), keyword()) :: api_result()
end
