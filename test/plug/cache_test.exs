defmodule Plug.CacheTest do
  use ExUnit.Case, async: true
  use Plug.Test

  use Timex

  test "no-op when method is POST" do
    resp = conn(:post, "/") |> call |> ok
    assert "invalidate" in traces(resp)
    assert "pass" in traces(resp)
    assert get_resp_header(resp, "Age") == []
  end

  test "no-op when method is PUT" do
    resp = conn(:post, "/") |> call |> ok
    assert "invalidate" in traces(resp)
    assert "pass" in traces(resp)
    assert get_resp_header(resp, "Age") == []
  end

  test "no-op when method is DELETE" do
    resp = conn(:post, "/") |> call |> ok
    assert "invalidate" in traces(resp)
    assert "pass" in traces(resp)
    assert get_resp_header(resp, "Age") == []
  end

  test "passes when private plug_cache var is set to force-pass" do
    resp = conn(:get, "/") |> put_private(:plug_cache_force_pass, true) |> call |> ok
    assert "pass" in traces(resp)
    assert get_resp_header(resp, "Age") == []
  end

  test "passes when Expect header is present" do
    resp = conn(:get, "/") |> put_req_header("Expect", "200-ok") |> call |> ok
    assert "pass" in traces(resp)
  end

  test "responds with 304 only if If-None-Match and If-Modified-Since both match" do
    {:ok, now} = Date.now |> DateFormat.format("{RFC1123}")
    {:ok, date} = Date.now |> Date.shift(secs: -1) |> DateFormat.format("{RFC1123}")

    response = &(respond_with(&1, 200, %{ "Etag" => "12345", "Last-Modified" =>  now}, "ok"))

    # Only Etag matches
    resp = conn(:get, "/")
           |> put_req_header("If-None-Match", "12345")
           |> put_req_header("If-Modified-Since", date)
           |> call
           |> response.()

    assert resp.status == 200

    # Only Last-Modified matches
    resp = conn(:get, "/")
           |> put_req_header("If-None-Match", "12346")
           |> put_req_header("If-Modified-Since", now)
           |> call
           |> response.()

    assert resp.status == 200

    # Both match
    resp = conn(:get, "/")
           |> put_req_header("If-None-Match", "12345")
           |> put_req_header("If-Modified-Since", now)
           |> call
           |> response.()

    assert resp.status == 304
  end

  def traces(resp) do
    case get_resp_header(resp, "X-Plug-Cache") do
      [] -> []
      [trace] -> String.split(trace, ", ")
    end
  end

  defp call(conn) do
    conn
    |> Plug.Cache.call(%{ metastore: %{}, entitystore: %{} })
  end

  defp ok(conn) do
    send_resp(conn, 200, "ok")
  end

  def respond_with(conn, status, headers, body) do
    Enum.reduce(headers, conn, fn({key, val}, acc) ->
      put_resp_header(acc, key, val)
    end)
    |> send_resp(status, body)
  end

end
