defmodule Plug.Cache.Response do
  defstruct status: nil, headers: %{}, body: ""
  @type headers :: %{ binary => binary }
  @type t :: %__MODULE__{status: integer, headers: headers, body: binary}
end
