defmodule Plug.Cache do

  @moduledoc """
  # HTTP Caching For Elixir

  Plug.Cache is suitable as a quick, drop-in component to enable HTTP caching
  for Plug-enabled applications that produce freshness (*Expires*, *Cache-Control*)
  and/or validation (*Last-Modified*, *ETag*) information.

  - Standards-based (RFC 2616 compliance)
  - Freshness/expiration based caching and validation
  - Supports HTTP Vary
  - Portable: 100% Elixir / works with any Plug-enabled framework

  ## Usage

      plug Plug.Cache,
        verbose: true,
        metastore: metastore,
        entitystore: entitystore
  """

  @behaviour Plug
  import Plug.Conn

  alias Plug.Cache.Lookup
  alias Plug.Cache.Pass
  alias Plug.Cache.Invalidate

  # Headers that MUST NOT be included with 304 Not Modified responses.
  #
  # http://tools.ietf.org/html/rfc2616#section-10.3.5
  @not_modified_omit_headers ~w[
    Allow
    Content-Encoding
    Content-Language
    Content-Length
    Content-MD5
    Content-Type
    Last-Modified
  ]


  ### PLUG

  def init(opts), do: opts

  def call(%Plug.Conn{} = conn, opts) do
    put_private(conn, :plug_cache_trace, [])
    |> handle_request(opts)
    |> register_before_send(&finish_call(&1, opts))
  end

  ### PRIVATE

  def handle_request(%Plug.Conn{method: "GET"} = conn, opts) do
    do_handle_request(conn, opts)
  end

  def handle_request(%Plug.Conn{method: "HEAD"} = conn, opts) do
    do_handle_request(conn, opts)
  end

  def handle_request(%Plug.Conn{} = conn, opts) do
    Invalidate.call(conn, opts)
  end

  # Allow other libraries to skip Plug.Cache
  defp do_handle_request(%Plug.Conn{private: %{:plug_cache_force_pass => true}} = conn, opts) do
    Pass.call(conn, opts)
  end

  defp do_handle_request(%Plug.Conn{req_headers: headers} = conn, opts) do
    do_handle_request(conn, opts, headers)
  end

  # Skip cache lookup when Expect header is set
  defp do_handle_request(conn, opts, [ {"Expect", _ } | _rest ]) do
    Pass.call(conn, opts)
  end

  defp do_handle_request(conn, opts, []) do
    Lookup.call(conn, opts)
  end

  defp do_handle_request(conn, opts, [ _ | rest ]) do
    do_handle_request(conn, opts, rest)
  end

  defp finish_call(conn, _opts) do
    conn
    |> put_resp_header("X-Plug-Cache", Enum.join(conn.private[:plug_cache_trace], ", "))
    |> cleanup_response
  end

  defp cleanup_response(%Plug.Conn{method: "GET"} = conn) do
    clean_not_modified(conn)
  end

  defp cleanup_response(%Plug.Conn{method: "HEAD"} = conn) do
    clean_not_modified(conn)
  end

  defp cleanup_response(conn), do: conn

  defp clean_not_modified(conn) do
    if not_modified?(conn) do
      Enum.reduce(@not_modified_omit_headers, conn, fn(header, acc) ->
        delete_resp_header(acc, header)
      end)
      |> resp(304, "")
    else
      clean_head(conn)
    end
  end

  # Determine if the response validators (ETag, Last-Modified) matches
  # a conditional value specified in request.
  defp not_modified?(%Plug.Conn{req_headers: headers} = conn) do
    not_modified?(conn, headers)
  end

  defp not_modified?(%Plug.Conn{}, []), do: false

  defp not_modified?(%Plug.Conn{} = conn, [{"If-None-Match", none_match} | _]) do
    not_modified?(
      none_match,
      get_resp_header(conn, "Etag"),
      get_req_header(conn, "If-Modified-Since"),
      get_resp_header(conn, "Last-Modified")
    )
  end

  defp not_modified?(%Plug.Conn{} = conn, [{"If-Modified-Since", last_modified} | _]) do
    get_resp_header(conn, "Last-Modified") == [last_modified]
  end

  defp not_modified?(%Plug.Conn{} = conn, [_ | rest]) do
    not_modified?(conn, rest)
  end

  # Respose does not have an Etag
  defp not_modified?(none_match, [], _modified_since, _last_modified) do
    req_etags = String.split(none_match, ~r/\s*,\s*/)

    "*" in req_etags
  end

  # Request does not contain If-Modified-Since
  defp not_modified?(none_match, [etag], [], _last_modified) do
    req_etags = String.split(none_match, ~r/\s*,\s*/)

    etag in req_etags || "*" in req_etags
  end

  # When request contains both If-None-Match and If-Modified-Since
  # both must match to be a 304
  defp not_modified?(none_match, etag, modified_since, last_modified) do
    modified_since == last_modified && not_modified?(none_match, etag, [], [])
  end

  # Make sure the body is empty
  defp clean_head(%Plug.Conn{method: "HEAD"} = conn) do
    resp(conn, conn.status, "")
  end

  defp clean_head(conn), do: conn

end
