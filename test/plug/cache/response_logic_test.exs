defmodule Plug.Cache.ResponseLogicTest do
  use ExUnit.Case, async: true

  use Timex

  alias Plug.Cache.Response
  alias Plug.Cache.ResponseLogic

  test "things ARE fresh when their max-age is greater than their Age" do
    headers = %{ "Cache-Control" => "public, max-age=300", "Age" => "299" }

    assert ResponseLogic.fresh?(%Response{headers: headers}) == true
  end

  test "things are NOT fresh when their max-age is less than than their Age" do
    headers = %{ "Cache-Control" => "public, max-age=300", "Age" => "301" }

    assert ResponseLogic.fresh?(%Response{headers: headers}) == false
  end

  test "things ARE fresh when their Age is less than Expries - Date" do
    date = DateFormat.format!(Date.now, "{RFC1123}")
    expires = DateFormat.format!( Date.shift(Date.now, secs: 78), "{RFC1123}" )
    headers = %{ "Age" => "55", "Date" => date, "Expires" => expires }

    assert ResponseLogic.fresh?(%Response{headers: headers}) == true
  end

  test "things are NOT fresh when their Age is more than Expries - Date" do
    date = DateFormat.format!(Date.now, "{RFC1123}")
    expires = DateFormat.format!( Date.shift(Date.now, secs: 78), "{RFC1123}" )
    headers = %{ "Age" => "80", "Date" => date, "Expires" => expires }

    assert ResponseLogic.fresh?(%Response{headers: headers}) == false
  end

  test "things ARE fresh when their max-age is greater than now - Date" do
    date = DateFormat.format!( Date.shift(Date.now, secs: -100), "{RFC1123}" )
    headers = %{ "Date" => date, "Cache-Control" => "public, max-age=300" }

    assert ResponseLogic.fresh?(%Response{headers: headers}) == true
  end

  test "things are NOT fresh when their max-age is less than now - Date" do
    date = DateFormat.format!( Date.shift(Date.now, secs: -100), "{RFC1123}" )
    headers = %{ "Date" => date, "Cache-Control" => "public, max-age=30" }

    assert ResponseLogic.fresh?(%Response{headers: headers}) == false
  end

  test "expires responses by setting their age to max-age" do
    headers = %{ "Age" => "30", "Cache-Control" => "public, max-age=300" }

    assert ResponseLogic.expire!(%Response{headers: headers}).headers["Age"] == "300"
  end
end
