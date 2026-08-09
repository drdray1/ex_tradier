defmodule ExTradier.WatchlistTest do
  use ExUnit.Case, async: true

  alias ExTradier.{Fixtures, Watchlist}

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

  describe "update_watchlist/3" do
    test "updates a watchlist" do
      Req.Test.expect(ExTradier.WatchlistTest.Update, fn conn ->
        assert conn.request_path == "/v1/watchlists/wl-tech-123"
        assert conn.method == "PUT"
        Req.Test.json(conn, Fixtures.watchlist_updated_response())
      end)

      client = Fixtures.test_client(ExTradier.WatchlistTest.Update)

      assert {:ok, %{"watchlist" => wl}} =
               Watchlist.update_watchlist(client, "wl-tech-123", %{name: "Updated Watchlist"})

      assert wl["name"] == "Updated Watchlist"
    end
  end

  describe "add_symbols/3" do
    test "adds symbols from a list" do
      Req.Test.expect(ExTradier.WatchlistTest.AddList, fn conn ->
        assert conn.request_path == "/v1/watchlists/wl-tech-123/symbols"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.watchlist_response())
      end)

      client = Fixtures.test_client(ExTradier.WatchlistTest.AddList)
      assert {:ok, _} = Watchlist.add_symbols(client, "wl-tech-123", ["GOOG", "AMZN"])
    end

    test "adds symbols from a string" do
      Req.Test.expect(ExTradier.WatchlistTest.AddString, fn conn ->
        assert conn.request_path == "/v1/watchlists/wl-tech-123/symbols"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.watchlist_response())
      end)

      client = Fixtures.test_client(ExTradier.WatchlistTest.AddString)
      assert {:ok, _} = Watchlist.add_symbols(client, "wl-tech-123", "GOOG,AMZN")
    end
  end

  describe "remove_symbol/3" do
    test "removes a symbol" do
      Req.Test.expect(ExTradier.WatchlistTest.Remove, fn conn ->
        assert conn.request_path == "/v1/watchlists/wl-tech-123/symbols/AAPL"
        assert conn.method == "DELETE"
        Req.Test.json(conn, Fixtures.watchlist_response())
      end)

      client = Fixtures.test_client(ExTradier.WatchlistTest.Remove)
      assert {:ok, _} = Watchlist.remove_symbol(client, "wl-tech-123", "AAPL")
    end
  end
end
