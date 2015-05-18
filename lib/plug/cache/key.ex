defmodule Plug.Cache.Key do

  def generate(%Plug.Conn{private: %{:plug_cache_cache_key => generator}} = conn) do
    generator.call(conn)
  end

  def generate(%Plug.Conn{} = conn) do
    parts = [conn.scheme, "://", conn.host]

    if conn.scheme == "https" && conn.port != 443 || conn.scheme == "http" && conn.port != 80 do
      parts = parts ++ [":", conn.port]
    end

    parts = parts ++ [conn.script_name, conn.path_info]

    if String.length(conn.query_string) > 0 do
      parts = parts ++ ["?", generate_query_string(conn.query_string)]
    end

    Enum.join(parts)
  end

  defp generate_query_string(qs) do
    String.split(qs, ~r/[&;] */ )
    |> Enum.map(&( URI.decode(&1) |> String.split("=", parts: 2) ))
    |> Enum.sort
    |> Enum.map(&( "#{URI.encode(Enum.at(&1,0))}=#{URI.encode(Enum.at(&1,1))}" ))
    |> Enum.join("&")
  end

end
