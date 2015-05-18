defmodule Plug.Cache.CacheControlTest do
  use ExUnit.Case, async: true
  doctest Plug.Cache.CacheControl

  alias Plug.Cache.CacheControl

  test "parses a cache control header" do
    assert CacheControl.parse("public, max-age=300") == %{ "public" => true, "max-age" => "300" }
  end

  test "converting to string" do
    options = %{"public" => true, "max-age" => 300}

    assert CacheControl.to_string(options) == "public, max-age=300"
  end
end
