defmodule Jido.Chat.Telegram.ExGramAdapter do
  @moduledoc """
  ExGram HTTP adapter backed by `Req`.
  """

  @compile {:no_warn_undefined, [ExGram.Adapter, ExGram.Config, ExGram.Encoder, Req.Request, Req.Steps, Req.Utils]}

  if Code.ensure_loaded?(ExGram.Adapter), do: @behaviour(ExGram.Adapter)

  alias Jido.Chat.Providers.Dependencies

  @base_url "https://api.telegram.org"
  @req_options [:base_url, :json, :form_multipart, :connect_options, :pool_timeout, :receive_timeout, :finch]

  @doc "Run an ExGram request with Req."
  def request(verb, path, body, opts \\ []) do
    with :ok <- Dependencies.telegram() do
      request_with_dependencies(verb, path, body, normalize_opts(opts))
    end
  end

  defp request_with_dependencies(verb, path, body, opts) do
    [method: coerce_verb(verb), url: path]
    |> Req.Request.new()
    |> Req.Request.register_options(@req_options)
    |> put_finch_options(opts)
    |> Req.Request.merge_options(request_options(opts))
    |> Req.Request.put_new_option(:base_url, ExGram.Config.get(:ex_gram, :base_url, @base_url))
    |> put_body_option(body)
    |> Req.Steps.put_base_url()
    |> Req.Request.append_request_steps(custom_encode: &custom_encode/1)
    |> Req.Request.append_response_steps(custom_decode: &custom_decode/1)
    |> Req.Request.run_request()
    |> handle_result()
  end

  defp coerce_verb(:get), do: :post
  defp coerce_verb(verb), do: verb

  defp normalize_opts(opts) when is_list(opts) do
    Enum.reduce(opts, [], fn
      {key, value}, acc when is_atom(key) ->
        Keyword.put(acc, key, value)

      {key, value}, acc when is_binary(key) ->
        case adapter_key(key) do
          nil -> acc
          atom_key -> Keyword.put(acc, atom_key, value)
        end

      _other, acc ->
        acc
    end)
  end

  defp normalize_opts(opts) when is_map(opts), do: opts |> Map.to_list() |> normalize_opts()
  defp normalize_opts(_opts), do: []

  defp request_options(opts) do
    opts
    |> Keyword.take([:base_url])
    |> maybe_put_base_url(Keyword.get(opts, :url))
  end

  defp put_finch_options(req, opts) do
    connection_options =
      cond do
        Keyword.has_key?(opts, :connect_options) -> [connect_options: opts[:connect_options]]
        opts[:finch] -> []
        true -> [connect_options: [timeout: Keyword.get(opts, :connect_timeout, 30_000)]]
      end

    req
    |> Req.Request.merge_options(
      connection_options ++
        [
          pool_timeout: Keyword.get(opts, :pool_timeout, 5_000),
          receive_timeout: Keyword.get(opts, :receive_timeout, 60_000)
        ]
    )
    |> maybe_merge_finch(Keyword.get(opts, :finch))
  end

  defp maybe_merge_finch(req, nil), do: req
  defp maybe_merge_finch(req, finch), do: Req.Request.merge_options(req, finch: finch)

  defp maybe_put_base_url(opts, nil), do: opts
  defp maybe_put_base_url(opts, url), do: Keyword.put(opts, :base_url, url)

  defp adapter_key("url"), do: :url
  defp adapter_key("base_url"), do: :base_url
  defp adapter_key("connect_timeout"), do: :connect_timeout
  defp adapter_key("connect_options"), do: :connect_options
  defp adapter_key("pool_timeout"), do: :pool_timeout
  defp adapter_key("receive_timeout"), do: :receive_timeout
  defp adapter_key("finch"), do: :finch
  defp adapter_key(_key), do: nil

  defp req_parts({:file, name, path}, parts), do: parts ++ [{name, File.stream!(path, 2048)}]

  defp req_parts({:file_content, name, content, filename}, parts),
    do: parts ++ [{name, {content, filename: filename}}]

  defp req_parts({name, value}, parts), do: parts ++ [{name, value}]

  defp put_body_option(req, {:multipart, parts}) do
    parts = Enum.reduce(parts, [], fn part, acc -> req_parts(part, acc) end)
    Req.Request.put_new_option(req, :form_multipart, parts)
  end

  defp put_body_option(req, body) when is_map(body),
    do: Req.Request.put_new_option(req, :json, body)

  defp custom_encode(request) do
    cond do
      data = request.options[:form_multipart] ->
        multipart = Req.Utils.encode_form_multipart(data)

        %{request | body: multipart.body}
        |> Req.Request.put_new_header("content-type", multipart.content_type)
        |> maybe_put_content_length(multipart.size)

      data = request.options[:json] ->
        %{request | body: ExGram.Adapter.encode(data)}
        |> Req.Request.put_new_header("content-type", "application/json")
        |> Req.Request.put_new_header("accept", "application/json")

      true ->
        request
    end
  end

  defp maybe_put_content_length(req, nil), do: req

  defp maybe_put_content_length(req, size),
    do: Req.Request.put_new_header(req, "content-length", Integer.to_string(size))

  defp custom_decode({request, response}) do
    case ExGram.Encoder.decode(response.body, keys: :atoms) do
      {:ok, decoded} -> {request, put_in(response.body, decoded)}
      {:error, error} -> {request, error}
    end
  end

  defp handle_result({_req, %{__struct__: Req.Response, status: status, body: %{ok: true, result: body}}})
       when status in 200..299,
       do: {:ok, body}

  defp handle_result({_req, %{__struct__: Req.Response, body: body}}),
    do: {:error, struct!(ExGram.Error, code: :response_status_not_match, message: ExGram.Adapter.encode(body))}

  defp handle_result({_req, exception}), do: {:error, struct!(ExGram.Error, code: exception)}
end
