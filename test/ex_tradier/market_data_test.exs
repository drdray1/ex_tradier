defmodule ExTradier.MarketDataTest do
  use ExUnit.Case, async: true

  alias ExTradier.{MarketData, Fixtures}

  describe "get_quotes/2" do
    test "fetches quotes for a symbol" do
      Req.Test.expect(ExTradier.MarketDataTest.Quotes, fn conn ->
        assert conn.request_path == "/v1/markets/quotes"
        Req.Test.json(conn, Fixtures.quote_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataTest.Quotes)
      assert {:ok, _} = MarketData.get_quotes(client, "AAPL")
    end
  end

  describe "post_quotes/2" do
    test "fetches quotes via POST" do
      Req.Test.expect(ExTradier.MarketDataTest.PostQuotes, fn conn ->
        assert conn.request_path == "/v1/markets/quotes"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.quotes_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataTest.PostQuotes)
      assert {:ok, _} = MarketData.post_quotes(client, ["AAPL", "MSFT"])
    end
  end

  describe "get_historical/3" do
    test "fetches historical data" do
      Req.Test.expect(ExTradier.MarketDataTest.Historical, fn conn ->
        assert conn.request_path == "/v1/markets/history"
        Req.Test.json(conn, Fixtures.historical_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataTest.Historical)
      assert {:ok, %{"history" => history}} = MarketData.get_historical(client, "AAPL")
      assert length(history["day"]) == 2
    end
  end

  describe "get_timesales/3" do
    test "fetches time and sales data" do
      Req.Test.expect(ExTradier.MarketDataTest.Timesales, fn conn ->
        assert conn.request_path == "/v1/markets/timesales"
        Req.Test.json(conn, Fixtures.timesales_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataTest.Timesales)
      assert {:ok, %{"series" => _}} = MarketData.get_timesales(client, "AAPL")
    end
  end

  describe "get_option_chains/3" do
    test "fetches option chains" do
      Req.Test.expect(ExTradier.MarketDataTest.Options, fn conn ->
        assert conn.request_path == "/v1/markets/options/chains"
        Req.Test.json(conn, Fixtures.option_chains_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataTest.Options)

      assert {:ok, %{"options" => options}} =
               MarketData.get_option_chains(client, "AAPL", %{expiration: "2024-01-19"})

      assert length(options["option"]) == 2
    end
  end

  describe "get_option_strikes/3" do
    test "fetches option strikes" do
      Req.Test.expect(ExTradier.MarketDataTest.Strikes, fn conn ->
        assert conn.request_path == "/v1/markets/options/strikes"
        Req.Test.json(conn, Fixtures.option_strikes_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataTest.Strikes)

      assert {:ok, %{"strikes" => strikes}} =
               MarketData.get_option_strikes(client, "AAPL", "2024-01-19")

      assert length(strikes["strike"]) == 5
    end
  end

  describe "get_option_expirations/2" do
    test "fetches expirations" do
      Req.Test.expect(ExTradier.MarketDataTest.Expirations, fn conn ->
        assert conn.request_path == "/v1/markets/options/expirations"
        Req.Test.json(conn, Fixtures.option_expirations_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataTest.Expirations)
      assert {:ok, %{"expirations" => _}} = MarketData.get_option_expirations(client, "AAPL")
    end
  end

  describe "lookup_option_symbols/3" do
    test "looks up option symbols" do
      Req.Test.expect(ExTradier.MarketDataTest.OptionLookup, fn conn ->
        assert conn.request_path == "/v1/markets/options/lookup"
        Req.Test.json(conn, Fixtures.option_lookup_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataTest.OptionLookup)
      assert {:ok, %{"symbols" => _}} = MarketData.lookup_option_symbols(client, "AAPL")
    end
  end

  describe "get_option_greeks/4" do
    test "fetches option greeks" do
      Req.Test.expect(ExTradier.MarketDataTest.Greeks, fn conn ->
        assert conn.request_path == "/v1/markets/options/greeks"
        Req.Test.json(conn, Fixtures.option_greeks_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataTest.Greeks)
      assert {:ok, %{"options" => _}} = MarketData.get_option_greeks(client, "AAPL", "2024-01-19")
    end
  end

  describe "get_option_chains_with_greeks/3" do
    test "fetches chains with greeks param" do
      Req.Test.expect(ExTradier.MarketDataTest.ChainsWithGreeks, fn conn ->
        assert conn.request_path == "/v1/markets/options/chains"
        Req.Test.json(conn, Fixtures.option_greeks_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataTest.ChainsWithGreeks)
      assert {:ok, _} = MarketData.get_option_chains_with_greeks(client, "AAPL")
    end
  end

  describe "search_symbols/2" do
    test "searches for symbols" do
      Req.Test.expect(ExTradier.MarketDataTest.Search, fn conn ->
        assert conn.request_path == "/v1/markets/search"
        Req.Test.json(conn, Fixtures.search_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataTest.Search)
      assert {:ok, %{"securities" => _}} = MarketData.search_symbols(client, "Apple")
    end
  end

  describe "lookup_symbol/2" do
    test "looks up symbol info" do
      Req.Test.expect(ExTradier.MarketDataTest.Lookup, fn conn ->
        assert conn.request_path == "/v1/markets/lookup"
        Req.Test.json(conn, Fixtures.lookup_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataTest.Lookup)
      assert {:ok, %{"securities" => _}} = MarketData.lookup_symbol(client, "AAPL")
    end
  end

  describe "get_clock/1" do
    test "fetches market clock" do
      Req.Test.expect(ExTradier.MarketDataTest.Clock, fn conn ->
        assert conn.request_path == "/v1/markets/clock"
        Req.Test.json(conn, Fixtures.clock_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataTest.Clock)
      assert {:ok, %{"clock" => clock}} = MarketData.get_clock(client)
      assert clock["state"] == "open"
    end
  end

  describe "get_calendar/2" do
    test "fetches market calendar" do
      Req.Test.expect(ExTradier.MarketDataTest.Calendar, fn conn ->
        assert conn.request_path == "/v1/markets/calendar"
        Req.Test.json(conn, Fixtures.calendar_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataTest.Calendar)
      assert {:ok, %{"calendar" => _}} = MarketData.get_calendar(client)
    end
  end

  describe "get_etb_list/1" do
    test "fetches ETB securities list" do
      Req.Test.expect(ExTradier.MarketDataTest.ETB, fn conn ->
        assert conn.request_path == "/v1/markets/etb"
        Req.Test.json(conn, Fixtures.etb_response())
      end)

      client = Fixtures.test_client(ExTradier.MarketDataTest.ETB)
      assert {:ok, %{"securities" => _}} = MarketData.get_etb_list(client)
    end
  end
end
