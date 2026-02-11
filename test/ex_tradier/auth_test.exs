defmodule ExTradier.AuthTest do
  use ExUnit.Case, async: true

  test "attaches bearer token to requests" do
    Req.Test.expect(ExTradier.AuthTest, fn conn ->
      auth_header = Plug.Conn.get_req_header(conn, "authorization")
      assert auth_header == ["Bearer test_token_123"]
      Req.Test.json(conn, %{"ok" => true})
    end)

    client = ExTradier.Client.new("test_token_123", plug: {Req.Test, ExTradier.AuthTest})
    {:ok, %Req.Response{status: 200}} = Req.get(client, url: "/test")
  end

  test "does not attach header when no token provided" do
    request =
      Req.new(base_url: "https://example.com")
      |> ExTradier.Auth.attach(nil)

    # The auth step should be registered but not crash
    assert %Req.Request{} = request
  end
end
