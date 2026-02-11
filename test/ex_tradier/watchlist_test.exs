defmodule ExTradier.WatchlistTest do
  use ExUnit.Case, async: true

  alias ExTradier.{Watchlist, Fixtures}

  describe "get_watchlists/1" do
    test "returns all watchlists" do
      Req.Test.expect(ExTradier.WatchlistTest.List, fn conn ->
        assert conn.request_path == "/v1/watchlists"
        Req.Test.json(conn, Fixtures.watchlists_response())
      end)

      client = Fixtures.test_client(ExTradier.WatchlistTest.List)
      assert {:ok, %{"watchlists" => watchlists}} = Watchlist.get_watchlists(client)
      assert length(watchlists["watchlist"]) == 2
    end
  end

  describe "get_watchlist/2" do
    test "returns a specific watchlist" do
      Req.Test.expect(ExTradier.WatchlistTest.Get, fn conn ->
        assert conn.request_path == "/v1/watchlists/wl-tech-123"
        Req.Test.json(conn, Fixtures.watchlist_response())
      end)

      client = Fixtures.test_client(ExTradier.WatchlistTest.Get)
      assert {:ok, %{"watchlist" => wl}} = Watchlist.get_watchlist(client, "wl-tech-123")
      assert wl["name"] == "Tech Stocks"
    end
  end

  describe "create_watchlist/2" do
    test "creates a watchlist" do
      Req.Test.expect(ExTradier.WatchlistTest.Create, fn conn ->
        assert conn.request_path == "/v1/watchlists"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.watchlist_created_response())
      end)

      client = Fixtures.test_client(ExTradier.WatchlistTest.Create)

      assert {:ok, %{"watchlist" => wl}} =
               Watchlist.create_watchlist(client, %{name: "New Watchlist"})

      assert wl["name"] == "New Watchlist"
    end
  end

  describe "delete_watchlist/2" do
    test "deletes a watchlist" do
      Req.Test.expect(ExTradier.WatchlistTest.Delete, fn conn ->
        assert conn.request_path == "/v1/watchlists/wl-tech-123"
        assert conn.method == "DELETE"
        Req.Test.json(conn, Fixtures.watchlist_deleted_response())
      end)

      client = Fixtures.test_client(ExTradier.WatchlistTest.Delete)
      assert {:ok, _} = Watchlist.delete_watchlist(client, "wl-tech-123")
    end
  end
end
