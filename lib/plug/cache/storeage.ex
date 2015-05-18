defmodule Plug.Cache.Storeage do
  @moduledoc """
  Module for serilzing, getting, and putting into / out of the entitystore and
  metastore.

  The entitystore will be filled with %{ digest => binary } content, where the
  digest is the SHA1 of the stored content.

  The metastore is a litle bit more complex. The cache_key is derived from
  Plug.Cache.Key and is based on the url of the request. Its content is a list
  of request / response tuples that have prevoisly hit this cache.  The request
  and response data are represented as maps of HTTP headers.  The stored
  touples are unique by request headers.

  The metastore response headers have a refrence to it's content's digest.
  """

  alias Plug.Cache.ResponseLogic
  alias Plug.Cache.Key
  alias Plug.Cache.Response

  @doc """
  """
  def lookup(conn, opts) do
    nil
  end

  @doc """
  Write a cache entry to the store under the given key. Existing
  entries are read and any that match the response are removed.
  """
  def store_response(%Plug.Conn{} = conn, %Response{} = response, opts) do
    { response, opts } = save_content_digest(response, opts)
    opts = save_response_meta(conn, response, opts)

    {:ok, response, opts}
  end

  @doc """
  Updates the cache so that every fresh entry for this request
  are expired.
  """
  def invalidate(%Plug.Conn{} = conn, %{ metastore: metastore } = opts) do
    cache_key = Key.generate(conn)
    entries = Dict.get(metastore, cache_key, [])

    updated_entries = Enum.map(entries, &invalidate_entry/1)

    if updated_entries != entries do
      opts = %{ opts | metastore: Dict.put(metastore, cache_key, updated_entries) }
    end

    opts
  end

  defp invalidate_entry({req, res}) do
    status = to_integer(res["X-Status"])
    headers = Map.delete(res, "X-Status")
    response = %Response{status: status, headers: headers}

    if ResponseLogic.fresh?(response) do
      {req, persisted_response(ResponseLogic.expire!(response))}
    else
      {req, res}
    end
  end

  defp save_content_digest(%Response{headers: %{ "X-Content-Digest" => nil }} = response,
                           %{ entitystore: entity_store } = opts ) do

    # write the response body to the entity store if this is the
    # original response.
    { entity_store, digest, size } = write_entity(entity_store, response.body)
    opts = %{ opts | entitystore: entity_store }
    response = %{ response | headers: Map.put(response.headers, "X-Content-Digest", digest) }
    unless response.headers["Transfer-Encoding"] do
      response = %{ response | headers: Map.put(response.headers, "Content-Length", size) }
    end
    response = %{ response | body: Dict.get(entity_store, digest, response.body) }

    { response, opts }
  end

  defp save_content_digest(response, opts) do
    # noop
    { response, opts }
  end

  defp save_response_meta(conn, response, %{ metastore: meta_store } = opts) do
    cache_key = Key.generate(conn)
    stored_env = persisted_request(conn)

    # read existing cache entries, remove non-varying, and add this one to
    # the list
    vary = response.headers["Vary"]

    entries = Dict.get(meta_store, cache_key, [])
    |> Enum.reject fn({saved_req_headers, saved_res_headers}) ->
      (vary == saved_res_headers["Vary"]) && requests_match?(vary, saved_req_headers, stored_env)
    end

    headers = persisted_response(response)
    |> Map.delete("Age")

    entries = [ {stored_env, headers} | entries ]
    %{ opts | metastore: Dict.put(meta_store, cache_key, entries) }
  end

  defp to_integer(amount) when is_binary(amount) do
    String.to_integer(amount)
  end

  defp to_integer(amount) when is_integer(amount) do
    amount
  end

  defp write_entity(entity_store, body) do
    length = String.length(body)
    sha = :crypto.hash(:sha, body) |> Base.encode16
    entity_store = Dict.put(entity_store, sha, body)
    { entity_store, sha, length }
  end

  # Determine whether the two environment hashes are non-varying based on
  # the vary response header value provided.
  defp requests_match?(nil, _, _) do
    true
  end

  defp requests_match?("", _, _) do
    true
  end

  defp requests_match?(vary, saved_req, req) do
    String.split(vary, ~r/[\s,]+/)
    |> Enum.all? fn(header) ->
      saved_req[header] == req[header]
    end
  end

  defp persisted_response(%Response{status: status, headers: headers}) do
    Map.put(headers, "X-Status", to_string(status))
  end

  defp persisted_request(%Plug.Conn{req_headers: headers}) do
    Enum.reduce headers, %{}, fn({key, val}, acc) ->
      Map.put(acc, key, val)
    end
  end

end
