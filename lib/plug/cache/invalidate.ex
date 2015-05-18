defmodule Plug.Cache.Invalidate do
  import Plug.Conn

  alias Plug.Cache.Storeage
  alias Plug.Cache.Pass

  @doc """
  Invalidate POST, PUT, DELETE and all methods not understood by this cache
  See RFC2616 13.10
  """
  def call(conn, opts) do
    opts = Storeage.invalidate(conn, opts)

    conn
    |> put_private(:plug_cache_trace, conn.private[:plug_cache_trace] ++ ["invalidate"])
    |> Pass.call(opts)
  end

end
