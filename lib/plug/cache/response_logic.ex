defmodule Plug.Cache.ResponseLogic do
  use Timex

  alias Plug.Cache.CacheControl
  alias Plug.Cache.Response

  # Status codes of responses that MAY be stored by a cache or used in reply
  # to a subsequent request.
  #
  # http://tools.ietf.org/html/rfc2616#section-13.4
  @cacheable_response_codes [
    200, # OK
    203, # Non-Authoritative Information
    300, # Multiple Choices
    301, # Moved Permanently
    302, # Found
    404, # Not Found
    410  # Gone
  ]

  @doc """
  Determine if the response is "fresh". Fresh responses may be served from
  cache without any interaction with the origin. A response is considered
  fresh when it includes a Cache-Control/max-age indicator or Expiration
  header and the calculated age is less than the freshness lifetime.
  """
  def fresh?(%Response{} = resp) do
    ttl = ttl(resp)

    ttl && ttl > 0
  end

  @doc """
  Mark the response stale by setting the Age header to be equal to the
  maximum age of the response.
  """
  def expire!(%Response{headers: headers} = resp) do
    if fresh?(resp) do
      %{ resp | headers: Map.put(headers, "Age", to_string(max_age(resp))) }
    else
      resp
    end
  end

  def ttl(%Response{} = resp) do
    maxage = max_age(resp)

    if maxage do
      maxage - age(resp)
    end
  end

  @doc """
  Determine if the response is worth caching under any circumstance. Responses
  marked "private" with an explicit Cache-Control directive are considered
  uncacheable

  Responses with neither a freshness lifetime (Expires, max-age) nor cache
  validator (Last-Modified, ETag) are considered uncacheable.
  """
  def cacheable?(%Response{status: status, headers: headers} = response) do
    cache_control = CacheControl.parse(headers["Cache-Control"])

    cond do
      !(status in @cacheable_response_codes) -> false
      CacheControl.no_store?(cache_control) -> false
      CacheControl.private?(cache_control) -> false
      validateable?(response) -> true
      fresh?(response) -> true
      true -> false
    end
  end

  @doc """
  Determine if the response includes headers that can be used to validate
  the response with the origin using a conditional GET request.
  """
  def validateable?(%Response{headers: headers}) do
    Map.has_key?(headers, "Last-Modified") || Map.has_key?(headers, "ETag")
  end

  defp max_age(%Response{headers: headers} = resp) do
    cache_control = CacheControl.parse(headers["Cache-Control"])

    CacheControl.reverse_max_age(cache_control) ||
    CacheControl.shared_max_age(cache_control) ||
    CacheControl.max_age(cache_control) ||
    (if expires = expires(resp), do: sec_diff(expires, date(resp)), else: nil)
  end

  def age(%Response{headers: headers} = resp) do
    case headers["Age"] do
      nil -> to_integer(Enum.max([sec_diff(now, date(resp)), 0]))
      age -> to_integer(age)
    end
  end

  defp date(%Response{headers: headers} = resp) do
    case headers["Date"] do
      nil -> now
      date -> httpdate(date)
    end
  end

  defp expires(%Response{headers: headers}) do
    case headers["Expires"] do
      nil -> nil
      expires -> httpdate(expires)
    end
  end

  defp now do
    Date.now
  end

  defp httpdate(date) do
    {:ok, date} = DateFormat.parse(date, "{RFC1123}")
    date
  end

  defp to_integer(num) when is_binary(num) do
    String.to_integer(num)
  end

  defp to_integer(num) when is_float(num) do
    Float.to_integer(num)
  end

  defp to_integer(num) when is_integer(num) do
    num
  end

  defp sec_diff(first, second) when is_integer(first) and is_integer(second) do
    first - second
  end

  defp sec_diff(%Timex.DateTime{} = first, second) do
    sec_diff(Date.convert(first, :secs), second)
  end

  defp sec_diff(first, %Timex.DateTime{} = second) do
    sec_diff(first, Date.convert(second, :secs))
  end

end

