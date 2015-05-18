defmodule Plug.Cache.CacheControl do
  @moduledoc """
  Parses Cache-Control headers and exposes the directives as a Map.
  Directives that do not have values are set to *true*.
  """

  @doc """
  Parses the given Cache-Control string into a map of options.

  ## Examples

      iex> Plug.Cache.CacheControl.parse "public, max-age=40"
      %{ "public" => true, "max-age" => "40" }

      iex> Plug.Cache.CacheControl.parse "must-revalidate, private, max-age=0"
      %{ "must-revalidate" => true, "private" => true, "max-age" => "0" }
  """
  def parse(value) when is_binary(value) do
    value
    |> String.replace(" ", "")
    |> String.split(",")
    |> Enum.reduce %{}, fn
      ("", acc) -> acc
      (part, acc) ->
        case String.split(part, "=", parts: 2) do
          ["", _value] -> acc
          [name, value] -> Map.put(acc, String.downcase(name), value)
          [""] -> acc
          [name] -> Map.put(acc, String.downcase(name), true)
        end
    end
  end

  def parse(nil), do: %{}
  def parse([]), do: %{}

  @doc """
  Indicates that the response MAY be cached by any cache, even if it
  would normally be non-cacheable or cacheable only within a non-
  shared cache.

  A response may be considered public without this directive if the
  private directive is not set and the request does not include an
  Authorization header.

  ## Examples

      iex> Plug.Cache.CacheControl.public? %{"public" => true, "max-age" => "40"}
      true

      iex> Plug.Cache.CacheControl.public? %{"must-revalidate" => true, "private" => true, "max-age" => "0"}
      false
  """
  def public?(%{ "public" => option }) do
    option
  end

  def public?(_) do
    false
  end

  @doc """
  Indicates that all or part of the response message is intended for
  a single user and MUST NOT be cached by a shared cache. This
  allows an origin server to state that the specified parts of the
  response are intended for only one user and are not a valid
  response for requests by other users. A private (non-shared) cache
  MAY cache the response.

  Note: This usage of the word private only controls where the
  response may be cached, and cannot ensure the privacy of the
  message content.

  ## Examples

      iex> Plug.Cache.CacheControl.private? %{"public" => true, "max-age" => "40"}
      false

      iex> Plug.Cache.CacheControl.private? %{"must-revalidate" => true, "private" => true, "max-age" => "0"}
      true
  """
  def private?(%{ "private" => option }) do
    option
  end

  def private?(_) do
    false
  end

  @doc """
  When set in a response, a cache MUST NOT use the response to satisfy a
  subsequent request without successful revalidation with the origin
  server. This allows an origin server to prevent caching even by caches
  that have been configured to return stale responses to client requests.

  Note that this does not necessary imply that the response may not be
  stored by the cache, only that the cache cannot serve it without first
  making a conditional GET request with the origin server.

  When set in a request, the server MUST NOT use a cached copy for its
  response. This has quite different semantics compared to the no-cache
  directive on responses. When the client specifies no-cache, it causes
  an end-to-end reload, forcing each cache to update their cached copies.

  ## Examples

      iex> Plug.Cache.CacheControl.no_cache? %{ "private" => true, "max-age" => "0", "no-cache" => true }
      true

      iex> Plug.Cache.CacheControl.no_cache? %{"must-revalidate" => true, "private" => true, "max-age" => "0"}
      false
  """
  def no_cache?(%{ "no-cache" => option }) do
    option
  end

  def no_cache?(_) do
    false
  end

  @doc """
  Indicates that the response MUST NOT be stored under any circumstances.

  The purpose of the no-store directive is to prevent the
  inadvertent release or retention of sensitive information (for
  example, on backup tapes). The no-store directive applies to the
  entire message, and MAY be sent either in a response or in a
  request. If sent in a request, a cache MUST NOT store any part of
  either this request or any response to it. If sent in a response,
  a cache MUST NOT store any part of either this response or the
  request that elicited it. This directive applies to both non-
  shared and shared caches. "MUST NOT store" in this context means
  that the cache MUST NOT intentionally store the information in
  non-volatile storage, and MUST make a best-effort attempt to
  remove the information from volatile storage as promptly as
  possible after forwarding it.

  The purpose of this directive is to meet the stated requirements
  of certain users and service authors who are concerned about
  accidental releases of information via unanticipated accesses to
  cache data structures. While the use of this directive might
  improve privacy in some cases, we caution that it is NOT in any
  way a reliable or sufficient mechanism for ensuring privacy. In
  particular, malicious or compromised caches might not recognize or
  obey this directive, and communications networks might be
  vulnerable to eavesdropping.

  ## Examples

      iex> Plug.Cache.CacheControl.no_store? %{ "max-age" => "0", "no-cache" => true, "no-store" => true }
      true

      iex> Plug.Cache.CacheControl.no_store? %{ "must-revalidate" => true, "private" => true, "max-age" => "0" }
      false
  """
  def no_store?(%{ "no-store" => option }) do
    option
  end

  def no_store?(_) do
    false
  end

  @doc """
  The expiration time of an entity MAY be specified by the origin
  server using the Expires header (see section 14.21). Alternatively,
  it MAY be specified using the max-age directive in a response. When
  the max-age cache-control directive is present in a cached response,
  the response is stale if its current age is greater than the age
  value given (in seconds) at the time of a new request for that
  resource. The max-age directive on a response implies that the
  response is cacheable (i.e., "public") unless some other, more
  restrictive cache directive is also present.

  If a response includes both an Expires header and a max-age
  directive, the max-age directive overrides the Expires header, even
  if the Expires header is more restrictive. This rule allows an origin
  server to provide, for a given response, a longer expiration time to
  an HTTP/1.1 (or later) cache than to an HTTP/1.0 cache. This might be
  useful if certain HTTP/1.0 caches improperly calculate ages or
  expiration times, perhaps due to desynchronized clocks.

  Many HTTP/1.0 cache implementations will treat an Expires value that
  is less than or equal to the response Date value as being equivalent
  to the Cache-Control response directive "no-cache". If an HTTP/1.1
  cache receives such a response, and the response does not include a
  Cache-Control header field, it SHOULD consider the response to be
  non-cacheable in order to retain compatibility with HTTP/1.0 servers.

  When the max-age directive is included in the request, it indicates
  that the client is willing to accept a response whose age is no
  greater than the specified time in seconds.

  ## Examples

      iex> Plug.Cache.CacheControl.max_age %{ "max-age" => "0", "no-cache" => true, "no-store" => true }
      0

      iex> Plug.Cache.CacheControl.max_age %{ "public" => true, "max-age" => "400" }
      400
  """
  def max_age(%{ "max-age" => age }) when is_binary(age) do
    String.to_integer(age)
  end

  def max_age(%{ "max-age" => age }) when is_integer(age) do
    age
  end

  def max_age(_) do
    nil
  end

  @doc """
  If a response includes an s-maxage directive, then for a shared
  cache (but not for a private cache), the maximum age specified by
  this directive overrides the maximum age specified by either the
  max-age directive or the Expires header. The s-maxage directive
  also implies the semantics of the proxy-revalidate directive. i.e.,
  that the shared cache must not use the entry after it becomes stale
  to respond to a subsequent request without first revalidating it with
  the origin server. The s-maxage directive is always ignored by a
  private cache.

  ## Examples

      iex> Plug.Cache.CacheControl.shared_max_age %{ "max-age" => "0", "no-cache" => true, "no-store" => true }
      nil

      iex> Plug.Cache.CacheControl.shared_max_age %{ "no-transform" => true,"public" => true, "max-age" => "300", "s-maxage" => "900" }
      900
  """
  def shared_max_age(%{ "s-maxage" => age }) when is_binary(age) do
    String.to_integer(age)
  end

  def shared_max_age(%{ "s-maxage" => age }) when is_integer(age) do
    age
  end

  def shared_max_age(_) do
    nil
  end

  @doc """
  If a response includes a r-maxage directive, then for a reverse cache
  (but not for a private or proxy cache), the maximum age specified by
  this directive overrides the maximum age specified by either the max-age
  directive, the s-maxage directive, or the Expires header. The r-maxage
  directive also implies the semantics of the proxy-revalidate directive.
  i.e., that the reverse cache must not use the entry after it becomes
  stale to respond to a subsequent request without first revalidating it
  with the origin server. The r-maxage directive is always ignored by
  private and proxy caches.

  ## Examples

      iex> Plug.Cache.CacheControl.reverse_max_age %{ "max-age" => "0", "no-cache" => true, "no-store" => true }
      nil

      iex> Plug.Cache.CacheControl.reverse_max_age %{ "no-transform" => true, "public" => true, "max-age" => "300", "r-maxage" => "900" }
      900
  """
  def reverse_max_age(%{ "r-maxage" => age }) when is_binary(age) do
    String.to_integer(age)
  end

  def reverse_max_age(%{ "r-maxage" => age }) when is_integer(age) do
    age
  end

  def reverse_max_age(_) do
    nil
  end

  @doc """
  Because a cache MAY be configured to ignore a server's specified
  expiration time, and because a client request MAY include a max-
  stale directive (which has a similar effect), the protocol also
  includes a mechanism for the origin server to require revalidation
  of a cache entry on any subsequent use. When the must-revalidate
  directive is present in a response received by a cache, that cache
  MUST NOT use the entry after it becomes stale to respond to a
  subsequent request without first revalidating it with the origin
  server. (I.e., the cache MUST do an end-to-end revalidation every
  time, if, based solely on the origin server's Expires or max-age
  value, the cached response is stale.)

  The must-revalidate directive is necessary to support reliable
  operation for certain protocol features. In all circumstances an
  HTTP/1.1 cache MUST obey the must-revalidate directive; in
  particular, if the cache cannot reach the origin server for any
  reason, it MUST generate a 504 (Gateway Timeout) response.

  Servers SHOULD send the must-revalidate directive if and only if
  failure to revalidate a request on the entity could result in
  incorrect operation, such as a silently unexecuted financial
  transaction. Recipients MUST NOT take any automated action that
  violates this directive, and MUST NOT automatically provide an
  unvalidated copy of the entity if revalidation fails.

  ## Examples

      iex> Plug.Cache.CacheControl.must_revalidate? %{ "must-revalidate" => true, "private" => true, "max-age" => "0" }
      true

      iex> Plug.Cache.CacheControl.must_revalidate? %{ "max-age" => "0", "no-cache" => true, "no-store" => true }
      false
  """
  def must_revalidate?(%{ "must-revalidate" => option }) do
    option
  end

  def must_revalidate?(_) do
    false
  end

  @doc """
  The proxy-revalidate directive has the same meaning as the must-
  revalidate directive, except that it does not apply to non-shared
  user agent caches. It can be used on a response to an
  authenticated request to permit the user's cache to store and
  later return the response without needing to revalidate it (since
  it has already been authenticated once by that user), while still
  requiring proxies that service many users to revalidate each time
  (in order to make sure that each user has been authenticated).
  Note that such authenticated responses also need the public cache
  control directive in order to allow them to be cached at all.

  ## Examples

      iex> Plug.Cache.CacheControl.proxy_revalidate? %{ "proxy-revalidate" => true, "private" => true, "max-age" => "0" }
      true

      iex> Plug.Cache.CacheControl.proxy_revalidate? %{ "max-age" => "0", "no-cache" => true, "no-store" => true }
      false
  """
  def proxy_revalidate?(%{ "proxy-revalidate" => option }) do
    option
  end

  def proxy_revalidate?(_) do
    false
  end

  @doc """
  Transforms a list of options into a proper Cache-Control header.

  ## Examples

      iex> Plug.Cache.CacheControl.to_string %{"public" => true, "max-age" => "40"}
      "public, max-age=40"

      iex> Plug.Cache.CacheControl.to_string %{"must-revalidate" => true, "private" => true, "max-age" => "0"}
      "must-revalidate, private, max-age=0"
  """
  def to_string(map) do
    {bools, vals} = Enum.reduce map, {[], []}, fn
      ({_key, nil}, acc) -> acc
      ({key, true}, {bools, vals}) -> {bools ++ [key], vals}
      ({key, val}, {bools, vals}) -> {bools, vals ++ ["#{key}=#{val}"]}
    end

    (Enum.sort(bools) ++ Enum.sort(vals)) |> Enum.join(", ")
  end
end
