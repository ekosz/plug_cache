defmodule Plug.Cache.StorageTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Plug.Cache.Storage
  alias Plug.Cache.Response

  test "stores meta information in the metastore" do
    body = "Pretty sweet content"
    digest = "ca463bf731ca57f0dacecced7e7be545d3907f70"
    req = conn(:get, "/")
    res_headers = Enum.reduce req.resp_headers, %{}, fn({key, val}, acc) ->
      Map.put(acc, key, val)
    end
    res = %Response{status: 200, headers: res_headers, body: body}

    {:ok, res, opts } = Storage.store_response(req, res, %{ metastore: %{}, entitystore: %{} })

    IO.inspect opts

    assert Map.get(opts[:entitystore], digest) == body
    assert  [{meta_req, meta_res}] = Map.get(opts[:metastore], "http://example.com")
  end
end

