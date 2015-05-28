defmodule Plug.Cache.Lookup do
  import Plug.Conn

  alias Plug.Cache.Storage
  alias Plug.Cache.Response
  alias Plug.Cache.ResponseLogic
  alias Plug.Cache.CacheControl

  @doc """
  Try to serve the response from cache. When a matching cache entry is
  found and is fresh, use it as the response without forwarding any
  request to the backend. When a matching cache entry is found but is
  stale, attempt to #validate the entry with the backend using conditional
  GET. When no matching cache entry is found, trigger #miss processing.
  """
  def call(%Plug.Conn{} = conn, opts) do
    cache_control = Enum.at(get_req_header(conn, "Cache-Control"), 0) |> CacheControl.parse
    pragma = Enum.at(get_req_header(conn, "Pragma"), 0)

    if CacheControl.no_cache?(cache_control) || pragma == "no-cache" do
      record(conn, "reload") |> fetch(opts)
    else
      lookup_entry(conn, opts)
    end
  end

  # Try to serve the response from cache. When a matching cache entry is
  # found and is fresh, use it as the response without forwarding any
  # request to the backend. When a matching cache entry is found but is
  # stale, attempt to validate the entry with the backend using conditional
  # GET. When no matching cache entry is found, trigger miss processing.
  defp lookup_entry(conn, opts) do
    case Storage.lookup(conn, opts) do
      nil -> record(conn, "miss") |> fetch(opts)
      entry -> lookup_entry(conn, opts, entry)
    end
  end

  defp lookup_entry(conn, opts, entry) do
    if fresh_enough?(entry, conn, opts) do
      record(conn, "fresh") |> serve_fresh(entry)
    else
      record(conn, "stale") |> validate(opts, entry)
    end
  end

  defp fresh_enough?(entry, conn, opts) do
    fresh_enough?(entry, conn, opts, {:fresh, ResponseLogic.fresh?(entry)})
  end

  defp fresh_enough?(_, _, _, {:fresh, false}), do: false
  defp fresh_enough?(_, _, %{ allow_revalidate: false } = _opts, {:fresh, true}), do: true

  defp fresh_enough?(entry, conn, _opts, {:fresh, true}) do
    cache_control = get_req_header(conn, "Cache-Control") |> CacheControl.parse
    max_age = CacheControl.max_age(cache_control)

    max_age && max_age > ResponseLogic.age(entry)
  end

  defp serve_fresh(conn, entry) do
    age = ResponseLogic.age(entry)
    entry = %{ entry | headers: Map.put(entry.headers, "Age", "#{age}") }
    conn_from_response(conn, entry)
  end

  defp validate(%Plug.Conn{req_headers: req_headers} = conn, opts, entry) do
    cached_etags = String.split(entry["Etag"], ~r/\s*,\s*/)
    request_etags = get_req_header(conn, "If-None-Match") |> Enum.join(",") |> String.split(~r/\s*,\s*/)
    etags = Enum.uniq(cached_etags ++ request_etags)
    etags = if Enum.empty?(etags), do: nil, else: Enum.join(", ")

    # Make sure the method is not HEAD. We want the body content.
    conn = %{ conn | method: "GET" }
    # Add our cached etag validator to the environment.
    # We keep the etags from the client to handle the case when the client
    # has a different private valid entry which is not cached here.
    conn = %{ conn | req_headers: Dict.put(req_headers, "If-None-Match", etags) }
    # Used cached last modified
    %{ conn | req_headers: Dict.put(req_headers, "If-Modified-Since", entry["Last-Modified"]) }
    |> register_before_send(&finish_validate(&1, opts, entry, cached_etags, request_etags))
  end

  defp finish_validate(%Plug.Conn{status: 304} = conn, opts, entry, cached_etags, request_etags) do
    conn = put_private(conn, :plug_cache_trace, conn.private[:plug_cache_trace] ++ ["valid"])
    etag = conn.resp_headers["Etag"]

    # Check if the response validated which is not cached here
    if etag && Enum.member?(request_etags, etag) && !Enum.member?(cached_etags, etag) do
      conn
    else
      finish_validate(conn, opts, entry)
    end
  end

  defp finish_validate(conn, opts, _entry, _, _) do
    conn
    |> put_private(:plug_cache_trace, conn.private[:plug_cache_trace] ++ ["invalidate"])
    |> store_validation(opts, response_from_conn(conn))
  end

  defp finish_validate(conn, opts, entry) do
    entry = Map.delete(entry, "Date")
    entry = Map.reduce(~w(Date Expires Cache-Control ETag Last-Modified), entry, fn(header, acc) ->
      if conn.resp_headers[header], do: Map.put(acc, header, conn.resp_headers[header]), else: acc
    end)

    store_validation(conn, opts, entry)
  end

  defp store_validation(conn, opts, entry) do
    entry = if ResponseLogic.cacheable?(entry), do: store(conn, entry, opts), else: entry
    conn_from_response(conn, entry)
  end

  # The cache missed or a reload is required. Forward the request to the
  # backend and determine whether the response should be stored. This allows
  # conditional / validation requests through to the backend but performs no
  # caching of the response when the backend returns a 304.
  defp fetch(conn, opts) do
    # Make sure the method is not HEAD. We want the body content.
    %{ conn | method: "GET" }
    |> register_before_send(&finish_fetch(&1, opts))
  end

  defp finish_fetch(conn, opts) do
    response = response_from_conn(conn) |> clean_cache_control(opts)
    response = if ResponseLogic.cacheable?(response), do: store(conn, response, opts), else: response

    conn_from_response(conn, response)
  end

  defp clean_cache_control(%Response{} = response, opts) do
    cache_control = CacheControl.parse(response.headers["Cache-Control"])
    |> clean_cache_control(response, opts)
    |> CacheControl.to_string

    %{ response | headers: Map.put(response.headers, "Cache-Control", cache_control) }
  end

  defp clean_cache_control(cache_control, response, opts) do
    cond do
      # Mark the response as explicitly private if any of the private
      # request headers are present and the response was not explicitly
      # declared public.
      private_request?(response.headers, opts) && !CacheControl.public?(cache_control) ->
        Map.merge(cache_control, %{ "Public" => false, "Private" => true })

      # assign a default TTL for the cache entry if none was specified in
      # the response; the must-revalidate cache control directive disables
      # default ttl assigment.
      default_ttl(opts) > 0 && ResponseLogic.ttl(response) == nil && !CacheControl.must_revalidate?(cache_control) ->
        Map.put(cache_control, "s-maxage", ResponseLogic.age(response) + default_ttl(opts))

      true -> cache_control
    end
  end

  defp response_from_conn(%Plug.Conn{status: status, resp_headers: headers, resp_body: body}) do
    code = Plug.Conn.Status.code(status)
    headers = Enum.reduce headers, %{}, fn({key, val}, acc) -> Map.put(acc, key, val) end
    %Response{status: code, headers: headers, body: body}
  end

  defp private_request?(headers, opts) do
    Map.get(opts, :private_header_keys, [])
    |> Enum.any?(fn(header) -> !!headers[header] end)
  end

  defp default_ttl(opts) do
    Map.get(opts, :default_ttl, 0)
  end

  # Write the respose to the cache
  defp store(conn, response, opts) do
    response = strip_ignored_headers(response, opts)
    {:ok, response, _opts } = Storage.store_response(conn, response, opts)
    %{ response | headers: Map.put(response.headers, "Age", "#{ResponseLogic.age(response)}") }
  end

  defp strip_ignored_headers(%Response{headers: headers} = response, opts) do
    ignored_headers = Map.get(opts, :ignored_headers, [])
    stripped_headers = Enum.reduce ignored_headers, headers, fn(header, headers) ->
      Map.delete(headers, header)
    end

    %{ response | headers: stripped_headers }
  end

  defp conn_from_response(conn, response) do
    Enum.reduce(response.headers, conn, fn({key, val}, acc) ->
      put_resp_header(acc, key, val)
    end)
    |> put_status(response.status)
  end

  defp record(conn, message) do
    put_private(conn, :plug_cache_trace, conn.private[:plug_cache_trace] ++ [message])
  end

end
