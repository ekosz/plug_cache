defmodule Plug.Cache.Lookup do
  import Plug.Conn

  alias Plug.Cache.Storeage
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
    case Storeage.lookup(conn, opts) do
      nil -> record(conn, "miss") |> fetch(opts)
      entry -> lookup_entry(conn, opts, entry)
    end
  end

  defp lookup_entry(conn, opts, entry) do
    if fresh_enough?(entry, conn, opts) do
      record(conn, "fresh") |> serve_fresh(opts, entry)
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

  defp serve_fresh(conn, opts, entry) do
    age = ResponseLogic.age(entry)
    entry = %{ entry | headers: Map.put(entry.headers, "Age", "#{age}") }
  end

  defp validate(conn, opts, entry) do

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

    if ResponseLogic.cacheable?(response) do
      response = store(conn, response, opts)
    end

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
    {:ok, response, opts } = Storeage.store_response(conn, response, opts)
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
