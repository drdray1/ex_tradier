defmodule ExTradier.MarketDataParamsTest do
  @moduledoc """
  Covers the request parameters Tradier documents for the market data endpoints,
  including the symbols-in-the-body contract for `post_quotes/3`.
  """
  use ExUnit.Case, async: true

  alias ExTradier.{Fixtures, MarketData}

  defp query(conn), do: URI.decode_query(conn.query_string)

  describe "post_quotes/3" do
    test "sends symbols in the form body, not the query string" do
      Req.Test.expect(ExTradier.MarketDataParamsTest.PostBody, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/markets/quotes"
        assert conn.query_string == ""
        assert conn.body_params["symbols"] == "AAPL,MSFT"

        Req.Test.json(conn, Fixtures.quotes_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataParamsTest.PostBody)
      assert {:ok, _} = MarketData.post_quotes(client, ["AAPL", "MSFT"])
    end

    test "keeps a long symbol list out of the URL" do
      symbols = for i <- 1..500, do: "SYM#{i}"

      Req.Test.expect(ExTradier.MarketDataParamsTest.LongList, fn conn ->
        assert byte_size(conn.request_path <> conn.query_string) < 100
        assert conn.body_params["symbols"] == Enum.join(symbols, ",")

        Req.Test.json(conn, Fixtures.quotes_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataParamsTest.LongList)
      assert {:ok, _} = MarketData.post_quotes(client, symbols)
    end

    test "forwards greeks in the body" do
      Req.Test.expect(ExTradier.MarketDataParamsTest.PostGreeks, fn conn ->
        assert conn.body_params["greeks"] == "true"
        assert conn.body_params["symbols"] == "AAPL"

        Req.Test.json(conn, Fixtures.quotes_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataParamsTest.PostGreeks)
      assert {:ok, _} = MarketData.post_quotes(client, "AAPL", greeks: true)
    end
  end

  describe "get_quotes/3" do
    test "forwards the greeks and includeLotSize options" do
      Req.Test.expect(ExTradier.MarketDataParamsTest.Quotes, fn conn ->
        params = query(conn)

        assert params["symbols"] == "AAPL"
        assert params["greeks"] == "true"
        assert params["includeLotSize"] == "true"

        Req.Test.json(conn, Fixtures.quote_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataParamsTest.Quotes)

      assert {:ok, _} =
               MarketData.get_quotes(client, "AAPL", greeks: true, includeLotSize: true)
    end

    test "a caller-supplied symbols param cannot override the requested symbol" do
      Req.Test.expect(ExTradier.MarketDataParamsTest.NoOverride, fn conn ->
        assert query(conn)["symbols"] == "AAPL"

        Req.Test.json(conn, Fixtures.quote_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataParamsTest.NoOverride)
      assert {:ok, _} = MarketData.get_quotes(client, "AAPL", %{symbols: "TSLA"})
    end

    test "joins a symbol list and still forwards options" do
      Req.Test.expect(ExTradier.MarketDataParamsTest.QuotesList, fn conn ->
        params = query(conn)

        assert params["symbols"] == "AAPL,MSFT"
        assert params["greeks"] == "true"

        Req.Test.json(conn, Fixtures.quotes_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataParamsTest.QuotesList)
      assert {:ok, _} = MarketData.get_quotes(client, ["AAPL", "MSFT"], greeks: true)
    end
  end

  describe "option endpoints" do
    test "get_option_strikes/4 forwards includeAllRoots" do
      Req.Test.expect(ExTradier.MarketDataParamsTest.Strikes, fn conn ->
        params = query(conn)

        assert params["symbol"] == "AAPL"
        assert params["expiration"] == "2024-01-19"
        assert params["includeAllRoots"] == "true"

        Req.Test.json(conn, Fixtures.option_strikes_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataParamsTest.Strikes)

      assert {:ok, _} =
               MarketData.get_option_strikes(client, "AAPL", "2024-01-19", includeAllRoots: true)
    end

    test "get_option_expirations/3 forwards strikes and expirationType" do
      Req.Test.expect(ExTradier.MarketDataParamsTest.Expirations, fn conn ->
        params = query(conn)

        assert params["symbol"] == "AAPL"
        assert params["strikes"] == "true"
        assert params["expirationType"] == "true"

        Req.Test.json(conn, Fixtures.option_expirations_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataParamsTest.Expirations)

      assert {:ok, _} =
               MarketData.get_option_expirations(client, "AAPL",
                 strikes: true,
                 expirationType: true
               )
    end

    test "get_option_chains_with_greeks/3 forces greeks on even if the caller disabled it" do
      Req.Test.expect(ExTradier.MarketDataParamsTest.ChainsGreeks, fn conn ->
        params = query(conn)

        assert params["greeks"] == "true"
        assert params["expiration"] == "2024-01-19"

        Req.Test.json(conn, Fixtures.option_chains_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataParamsTest.ChainsGreeks)

      assert {:ok, _} =
               MarketData.get_option_chains_with_greeks(client, "AAPL", %{
                 expiration: "2024-01-19",
                 greeks: false
               })
    end
  end

  describe "search and lookup" do
    test "search_symbols/3 forwards indexes" do
      Req.Test.expect(ExTradier.MarketDataParamsTest.Search, fn conn ->
        params = query(conn)

        assert params["q"] == "apple"
        assert params["indexes"] == "false"

        Req.Test.json(conn, Fixtures.search_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataParamsTest.Search)
      assert {:ok, _} = MarketData.search_symbols(client, "apple", indexes: false)
    end

    test "lookup_symbol/3 forwards exchanges and types" do
      Req.Test.expect(ExTradier.MarketDataParamsTest.Lookup, fn conn ->
        params = query(conn)

        assert params["q"] == "AAPL"
        assert params["exchanges"] == "Q,N"
        assert params["types"] == "stock,etf"

        Req.Test.json(conn, Fixtures.lookup_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataParamsTest.Lookup)

      assert {:ok, _} =
               MarketData.lookup_symbol(client, "AAPL", exchanges: "Q,N", types: "stock,etf")
    end
  end

  describe "calendar and clock" do
    test "get_calendar/2 forwards month and year" do
      Req.Test.expect(ExTradier.MarketDataParamsTest.Calendar, fn conn ->
        params = query(conn)

        assert params["month"] == "1"
        assert params["year"] == "2024"

        Req.Test.json(conn, Fixtures.calendar_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataParamsTest.Calendar)
      assert {:ok, _} = MarketData.get_calendar(client, %{month: 1, year: 2024})
    end

    test "get_clock/2 forwards delayed" do
      Req.Test.expect(ExTradier.MarketDataParamsTest.Clock, fn conn ->
        assert query(conn)["delayed"] == "true"

        Req.Test.json(conn, Fixtures.clock_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataParamsTest.Clock)
      assert {:ok, _} = MarketData.get_clock(client, delayed: true)
    end

    test "get_clock/1 sends no query params" do
      Req.Test.expect(ExTradier.MarketDataParamsTest.ClockBare, fn conn ->
        assert conn.query_string == ""

        Req.Test.json(conn, Fixtures.clock_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataParamsTest.ClockBare)
      assert {:ok, _} = MarketData.get_clock(client)
    end
  end

  describe "historical data" do
    test "get_historical/3 drops nil bounds instead of sending empty params" do
      Req.Test.expect(ExTradier.MarketDataParamsTest.Historical, fn conn ->
        params = query(conn)

        assert params["symbol"] == "AAPL"
        assert params["interval"] == "daily"
        refute Map.has_key?(params, "start")
        refute Map.has_key?(params, "end")

        Req.Test.json(conn, Fixtures.historical_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataParamsTest.Historical)

      assert {:ok, _} =
               MarketData.get_historical(client, "AAPL", %{
                 interval: "daily",
                 start: nil,
                 end: nil
               })
    end

    test "get_timesales/3 forwards the session filter" do
      Req.Test.expect(ExTradier.MarketDataParamsTest.Timesales, fn conn ->
        params = query(conn)

        assert params["symbol"] == "AAPL"
        assert params["interval"] == "5min"
        assert params["session_filter"] == "all"

        Req.Test.json(conn, Fixtures.timesales_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataParamsTest.Timesales)

      assert {:ok, _} =
               MarketData.get_timesales(client, "AAPL",
                 interval: "5min",
                 session_filter: "all"
               )
    end
  end
end
