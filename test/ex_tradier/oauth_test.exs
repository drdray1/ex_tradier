defmodule ExTradier.OAuthTest do
  use ExUnit.Case, async: true

  alias ExTradier.{Fixtures, OAuth}

  doctest ExTradier.OAuth

  describe "scopes/0" do
    test "returns every scope Tradier documents" do
      assert OAuth.scopes() == [:read, :write, :market, :trade, :stream]
    end
  end

  describe "authorize_url/2" do
    test "includes only the client id when no options are given" do
      assert OAuth.authorize_url("abc123") ==
               "https://api.tradier.com/v1/oauth/authorize?client_id=abc123"
    end

    test "joins a list of scopes with commas" do
      url = OAuth.authorize_url("abc123", scope: [:read, :trade, :market])

      assert URI.decode_query(URI.parse(url).query)["scope"] == "read,trade,market"
    end

    test "accepts a single scope atom or a preformatted string" do
      assert OAuth.authorize_url("abc", scope: :read) =~ "scope=read"
      assert OAuth.authorize_url("abc", scope: "read,trade") =~ "scope=read%2Ctrade"
    end

    test "omits scope when given an empty list" do
      refute OAuth.authorize_url("abc123", scope: []) =~ "scope"
    end

    test "url-encodes the state" do
      url = OAuth.authorize_url("abc123", state: "a b&c")

      assert URI.decode_query(URI.parse(url).query)["state"] == "a b&c"
    end

    test "honours a base_url override" do
      assert OAuth.authorize_url("abc", base_url: "https://example.test/authorize") ==
               "https://example.test/authorize?client_id=abc"
    end
  end

  describe "create_access_token/4" do
    test "posts the authorization code with basic auth" do
      Req.Test.expect(ExTradier.OAuthTest.AccessToken, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/oauth/accesstoken"

        assert Plug.Conn.get_req_header(conn, "authorization") == [
                 "Basic " <> Base.encode64("client-id:client-secret")
               ]

        assert conn.body_params["grant_type"] == "authorization_code"
        assert conn.body_params["code"] == "auth-code"

        Req.Test.json(conn, Fixtures.access_token_response())
      end)

      assert {:ok, token} =
               OAuth.create_access_token("client-id", "client-secret", "auth-code",
                 plug: {Req.Test, ExTradier.OAuthTest.AccessToken}
               )

      assert token["access_token"] == "MTIzNDU2Nzg5"
      assert token["expires_in"] == 86_399
    end

    test "returns a tagged error for a rejected exchange" do
      Req.Test.expect(ExTradier.OAuthTest.BadCode, fn conn ->
        Plug.Conn.send_resp(conn, 401, "")
      end)

      assert {:error, :unauthorized} =
               OAuth.create_access_token("client-id", "client-secret", "expired-code",
                 plug: {Req.Test, ExTradier.OAuthTest.BadCode}
               )
    end
  end

  describe "refresh_access_token/4" do
    test "posts the refresh token grant" do
      Req.Test.expect(ExTradier.OAuthTest.Refresh, fn conn ->
        assert conn.request_path == "/v1/oauth/refreshtoken"
        assert conn.body_params["grant_type"] == "refresh_token"
        assert conn.body_params["refresh_token"] == "cmVmcmVzaC10b2tlbg"

        Req.Test.json(conn, Fixtures.access_token_response())
      end)

      assert {:ok, %{"access_token" => _}} =
               OAuth.refresh_access_token("client-id", "client-secret", "cmVmcmVzaC10b2tlbg",
                 plug: {Req.Test, ExTradier.OAuthTest.Refresh}
               )
    end
  end

  describe "expires_at/2" do
    test "adds expires_in seconds to the reference time" do
      now = ~U[2026-08-09 12:00:00Z]

      assert OAuth.expires_at(Fixtures.access_token_response(), now) ==
               ~U[2026-08-10 11:59:59Z]
    end

    test "returns nil when the token carries no expiry" do
      assert OAuth.expires_at(%{"access_token" => "abc"}) == nil
    end

    test "returns nil when expires_in is not an integer" do
      assert OAuth.expires_at(%{"expires_in" => "86399"}) == nil
    end
  end
end
