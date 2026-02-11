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
end
