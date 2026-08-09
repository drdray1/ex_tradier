defmodule ExTradier.ClientConfigTest do
  @moduledoc """
  Application env is global, so these run synchronously to avoid changing the
  environment out from under concurrently running tests.
  """
  use ExUnit.Case, async: false

  alias ExTradier.{Client, Fixtures}

  describe "new/0 from application config" do
    setup do
      on_exit(fn ->
        Application.delete_env(:ex_tradier, :api_token)
        Application.delete_env(:ex_tradier, :sandbox)
      end)
    end

    test "builds a client that sends the configured token as a bearer credential" do
      Application.put_env(:ex_tradier, :api_token, "configured-token")

      Req.Test.expect(ExTradier.ClientConfigTest.Configured, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer configured-token"]
        Req.Test.json(conn, Fixtures.profile_response())
      end)

      assert {:ok, %Req.Response{status: 200}} =
               Req.get(Client.new(),
                 url: "/user/profile",
                 plug: {Req.Test, ExTradier.ClientConfigTest.Configured}
               )
    end

    test "defaults to sandbox" do
      Application.put_env(:ex_tradier, :api_token, "configured-token")

      assert Client.new().options[:base_url] == Client.sandbox_url()
    end

    test "honours the configured sandbox flag" do
      Application.put_env(:ex_tradier, :api_token, "configured-token")
      Application.put_env(:ex_tradier, :sandbox, false)

      assert Client.new().options[:base_url] == Client.production_url()
    end

    test "an explicit :sandbox option still wins over config" do
      Application.put_env(:ex_tradier, :sandbox, false)

      assert Client.new("token", sandbox: true).options[:base_url] == Client.sandbox_url()
    end

    test "new/2 picks up the configured sandbox flag" do
      Application.put_env(:ex_tradier, :sandbox, false)

      assert Client.new("token").options[:base_url] == Client.production_url()
    end

    test "raises a helpful error when no token is configured" do
      assert_raise ArgumentError, ~r/no Tradier API token configured/, fn -> Client.new() end
    end
  end
end
