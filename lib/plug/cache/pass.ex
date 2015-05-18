defmodule Plug.Cache.Pass do
  import Plug.Conn

  def call(conn, _opts) do
    conn
    |> put_private(:plug_cache_trace, conn.private[:plug_cache_trace] ++ ["pass"])
  end

end
