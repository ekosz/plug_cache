defmodule Plug.Cache.KeyTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Plug.Cache.Key

  test "generates a key for a request" do
    conn = conn(:get, "/")

    assert Key.generate(conn) == "http://www.example.com"
  end

  test "adds the query string if there is one" do
    conn = conn(:get, "/?this=is&very=cool")

    assert Key.generate(conn) == "http://www.example.com?this=is&very=cool"
  end

  test "it sorts the query params" do
    conn = conn(:get, "/?z=last&a=first")

    assert Key.generate(conn) == "http://www.example.com?a=first&z=last"
  end

  test "it decodes the query string if need to" do
    conn = conn(:get, "/?x=q&a=b&%78=c")

    assert Key.generate(conn) == "http://www.example.com?a=b&x=c&x=q"
  end
end


