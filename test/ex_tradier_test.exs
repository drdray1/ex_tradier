defmodule ExTradierTest do
  use ExUnit.Case, async: true

  alias ExTradier.Fixtures

  describe "extract_account_id/1" do
    test "extracts account ID from profile with multiple accounts" do
      profile = Fixtures.profile_response()
      assert ExTradier.extract_account_id(profile) == "VA000001"
    end

    test "extracts account ID from profile with single account" do
      profile = Fixtures.profile_single_account_response()
      assert ExTradier.extract_account_id(profile) == "VA000001"
    end

    test "returns nil for invalid profile" do
      assert ExTradier.extract_account_id(%{}) == nil
    end

    test "returns nil when account list has no account_number" do
      profile = %{"profile" => %{"account" => [%{"name" => "Test"}]}}
      assert ExTradier.extract_account_id(profile) == nil
    end
  end

  describe "normalize_quote/1" do
    test "extracts single quote from response" do
      response = %{
        "quotes" => %{
          "quote" => %{"symbol" => "AAPL", "last" => 150.0}
        }
      }

      quote = ExTradier.normalize_quote(response)
      assert quote["symbol"] == "AAPL"
      assert quote["last"] == 150.0
    end

    test "passes through array of quotes" do
      quotes_list = [
        %{"symbol" => "AAPL", "last" => 150.0},
        %{"symbol" => "MSFT", "last" => 300.0}
      ]

      response = %{"quotes" => %{"quote" => quotes_list}}
      assert ExTradier.normalize_quote(response) == quotes_list
    end

    test "returns original data if not in expected format" do
      data = %{"other" => "data"}
      assert ExTradier.normalize_quote(data) == data
    end
  end

  describe "normalize_positions/1" do
    test "extracts single position as list" do
      response = %{
        "positions" => %{
          "position" => %{"symbol" => "AAPL", "quantity" => 100}
        }
      }

      positions = ExTradier.normalize_positions(response)
      assert length(positions) == 1
      assert hd(positions)["symbol"] == "AAPL"
    end

    test "passes through array of positions" do
      positions_list = [
        %{"symbol" => "AAPL", "quantity" => 100},
        %{"symbol" => "MSFT", "quantity" => 50}
      ]

      response = %{"positions" => %{"position" => positions_list}}
      assert ExTradier.normalize_positions(response) == positions_list
    end

    test "returns empty list for null positions" do
      response = %{"positions" => "null"}
      assert ExTradier.normalize_positions(response) == []
    end

    test "returns empty list for invalid format" do
      assert ExTradier.normalize_positions(%{}) == []
    end
  end

  describe "place_order/3" do
    test "dispatches equity order" do
      Req.Test.expect(ExTradierTest.PlaceEquity, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradierTest.PlaceEquity)

      params = %{
        class: "equity",
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "market",
        duration: "day"
      }

      assert {:ok, %{"order" => _}} = ExTradier.place_order(client, "VA000001", params)
    end

    test "dispatches option order" do
      Req.Test.expect(ExTradierTest.PlaceOption, fn conn ->
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradierTest.PlaceOption)

      params = %{
        class: "option",
        symbol: "AAPL",
        option_symbol: "AAPL240119C00150000",
        side: "buy_to_open",
        quantity: 1,
        type: "market",
        duration: "day"
      }

      assert {:ok, %{"order" => _}} = ExTradier.place_order(client, "VA000001", params)
    end

    test "dispatches multileg order" do
      Req.Test.expect(ExTradierTest.PlaceMultileg, fn conn ->
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradierTest.PlaceMultileg)

      params = %{
        class: "multileg",
        symbol: "AAPL",
        type: "market",
        duration: "day",
        legs: [
          %{option_symbol: "AAPL240119C00150000", side: "buy_to_open", quantity: 1},
          %{option_symbol: "AAPL240119C00155000", side: "sell_to_open", quantity: 1}
        ]
      }

      assert {:ok, %{"order" => _}} = ExTradier.place_order(client, "VA000001", params)
    end

    test "dispatches combo order" do
      Req.Test.expect(ExTradierTest.PlaceCombo, fn conn ->
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradierTest.PlaceCombo)

      params = %{
        class: "combo",
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "market",
        duration: "day"
      }

      assert {:ok, %{"order" => _}} = ExTradier.place_order(client, "VA000001", params)
    end

    test "defaults to equity when class not specified" do
      Req.Test.expect(ExTradierTest.PlaceDefault, fn conn ->
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradierTest.PlaceDefault)

      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "market",
        duration: "day"
      }

      assert {:ok, %{"order" => _}} = ExTradier.place_order(client, "VA000001", params)
    end
  end

  # ============================================================================
  # Facade delegate tests — exercise delegates through ExTradier module
  # ============================================================================

  describe "get_quote/2 (facade)" do
    test "fetches a single quote" do
      Req.Test.expect(ExTradierTest.FacadeQuote, fn conn ->
        assert conn.request_path == "/v1/markets/quotes"
        Req.Test.json(conn, Fixtures.quote_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeQuote)
      assert {:ok, _} = ExTradier.get_quote(client, "AAPL")
    end
  end

  describe "delegate: get_profile/1" do
    test "delegates to User.get_profile" do
      Req.Test.expect(ExTradierTest.FacadeProfile, fn conn ->
        assert conn.request_path == "/v1/user/profile"
        Req.Test.json(conn, Fixtures.profile_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeProfile)
      assert {:ok, %{"profile" => _}} = ExTradier.get_profile(client)
    end
  end

  describe "delegate: get_balances/2" do
    test "delegates to User.get_balances" do
      Req.Test.expect(ExTradierTest.FacadeBalances, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/balances"
        Req.Test.json(conn, Fixtures.balances_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeBalances)
      assert {:ok, %{"balances" => _}} = ExTradier.get_balances(client, "VA000001")
    end
  end

  describe "delegate: get_positions/2" do
    test "delegates to User.get_positions" do
      Req.Test.expect(ExTradierTest.FacadePositions, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/positions"
        Req.Test.json(conn, Fixtures.positions_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadePositions)
      assert {:ok, %{"positions" => _}} = ExTradier.get_positions(client, "VA000001")
    end
  end

  describe "delegate: get_history/3" do
    test "delegates to User.get_history" do
      Req.Test.expect(ExTradierTest.FacadeHistory, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/history"
        Req.Test.json(conn, Fixtures.history_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeHistory)
      assert {:ok, %{"history" => _}} = ExTradier.get_history(client, "VA000001")
    end
  end

  describe "delegate: get_gainloss/3" do
    test "delegates to User.get_gainloss" do
      Req.Test.expect(ExTradierTest.FacadeGainloss, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/gainloss"
        Req.Test.json(conn, Fixtures.gainloss_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeGainloss)
      assert {:ok, %{"gainloss" => _}} = ExTradier.get_gainloss(client, "VA000001")
    end
  end

  describe "delegate: get_cost_basis/3" do
    test "delegates to User.get_cost_basis" do
      Req.Test.expect(ExTradierTest.FacadeCostBasis, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/costbasis"
        Req.Test.json(conn, Fixtures.cost_basis_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeCostBasis)
      assert {:ok, %{"costbasis" => _}} = ExTradier.get_cost_basis(client, "VA000001", "AAPL")
    end
  end

  describe "delegate: get_quotes/2" do
    test "delegates to MarketData.get_quotes" do
      Req.Test.expect(ExTradierTest.FacadeQuotes, fn conn ->
        assert conn.request_path == "/v1/markets/quotes"
        Req.Test.json(conn, Fixtures.quotes_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeQuotes)
      assert {:ok, _} = ExTradier.get_quotes(client, ["AAPL", "MSFT"])
    end
  end

  describe "delegate: get_historical/3" do
    test "delegates to MarketData.get_historical" do
      Req.Test.expect(ExTradierTest.FacadeHistorical, fn conn ->
        assert conn.request_path == "/v1/markets/history"
        Req.Test.json(conn, Fixtures.historical_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeHistorical)
      assert {:ok, _} = ExTradier.get_historical(client, "AAPL")
    end
  end

  describe "delegate: get_timesales/3" do
    test "delegates to MarketData.get_timesales" do
      Req.Test.expect(ExTradierTest.FacadeTimesales, fn conn ->
        assert conn.request_path == "/v1/markets/timesales"
        Req.Test.json(conn, Fixtures.timesales_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeTimesales)
      assert {:ok, _} = ExTradier.get_timesales(client, "AAPL")
    end
  end

  describe "delegate: get_option_chains/3" do
    test "delegates to MarketData" do
      Req.Test.expect(ExTradierTest.FacadeChains, fn conn ->
        assert conn.request_path == "/v1/markets/options/chains"
        Req.Test.json(conn, Fixtures.option_chains_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeChains)
      assert {:ok, _} = ExTradier.get_option_chains(client, "AAPL")
    end
  end

  describe "delegate: get_option_expirations/2" do
    test "delegates to MarketData" do
      Req.Test.expect(ExTradierTest.FacadeExpirations, fn conn ->
        assert conn.request_path == "/v1/markets/options/expirations"
        Req.Test.json(conn, Fixtures.option_expirations_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeExpirations)
      assert {:ok, _} = ExTradier.get_option_expirations(client, "AAPL")
    end
  end

  describe "delegate: get_option_strikes/3" do
    test "delegates to MarketData" do
      Req.Test.expect(ExTradierTest.FacadeStrikes, fn conn ->
        assert conn.request_path == "/v1/markets/options/strikes"
        Req.Test.json(conn, Fixtures.option_strikes_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeStrikes)
      assert {:ok, _} = ExTradier.get_option_strikes(client, "AAPL", "2024-01-19")
    end
  end

  describe "delegate: search_symbols/2" do
    test "delegates to MarketData" do
      Req.Test.expect(ExTradierTest.FacadeSearch, fn conn ->
        assert conn.request_path == "/v1/markets/search"
        Req.Test.json(conn, Fixtures.search_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeSearch)
      assert {:ok, _} = ExTradier.search_symbols(client, "AAPL")
    end
  end

  describe "delegate: lookup_symbol/2" do
    test "delegates to MarketData" do
      Req.Test.expect(ExTradierTest.FacadeLookup, fn conn ->
        assert conn.request_path == "/v1/markets/lookup"
        Req.Test.json(conn, Fixtures.lookup_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeLookup)
      assert {:ok, _} = ExTradier.lookup_symbol(client, "AAPL")
    end
  end

  describe "delegate: get_calendar/2" do
    test "delegates to MarketData" do
      Req.Test.expect(ExTradierTest.FacadeCalendar, fn conn ->
        assert conn.request_path == "/v1/markets/calendar"
        Req.Test.json(conn, Fixtures.calendar_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeCalendar)
      assert {:ok, _} = ExTradier.get_calendar(client)
    end
  end

  describe "delegate: get_clock/1" do
    test "delegates to MarketData" do
      Req.Test.expect(ExTradierTest.FacadeClock, fn conn ->
        assert conn.request_path == "/v1/markets/clock"
        Req.Test.json(conn, Fixtures.clock_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeClock)
      assert {:ok, _} = ExTradier.get_clock(client)
    end
  end

  describe "delegate: get_etb_list/1" do
    test "delegates to MarketData" do
      Req.Test.expect(ExTradierTest.FacadeEtb, fn conn ->
        assert conn.request_path == "/v1/markets/etb"
        Req.Test.json(conn, Fixtures.etb_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeEtb)
      assert {:ok, _} = ExTradier.get_etb_list(client)
    end
  end

  describe "delegate: preview_order/3" do
    test "delegates to Trading" do
      Req.Test.expect(ExTradierTest.FacadePreview, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders"
        Req.Test.json(conn, Fixtures.order_preview_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadePreview)

      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "market",
        duration: "day"
      }

      assert {:ok, _} = ExTradier.preview_order(client, "VA000001", params)
    end
  end

  describe "delegate: modify_order/4" do
    test "delegates to Trading" do
      Req.Test.expect(ExTradierTest.FacadeModify, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders/123"
        assert conn.method == "PUT"
        Req.Test.json(conn, Fixtures.order_modified_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeModify)
      assert {:ok, _} = ExTradier.modify_order(client, "VA000001", "123", %{type: "limit"})
    end
  end

  describe "delegate: cancel_order/3" do
    test "delegates to Trading" do
      Req.Test.expect(ExTradierTest.FacadeCancel, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders/123"
        assert conn.method == "DELETE"
        Req.Test.json(conn, Fixtures.order_cancelled_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeCancel)
      assert {:ok, _} = ExTradier.cancel_order(client, "VA000001", "123")
    end
  end

  describe "delegate: get_orders/3" do
    test "delegates to Trading" do
      Req.Test.expect(ExTradierTest.FacadeOrders, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders"
        Req.Test.json(conn, Fixtures.orders_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeOrders)
      assert {:ok, _} = ExTradier.get_orders(client, "VA000001")
    end
  end

  describe "delegate: get_order/3" do
    test "delegates to Trading" do
      Req.Test.expect(ExTradierTest.FacadeOrder, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders/123456"
        Req.Test.json(conn, Fixtures.order_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeOrder)
      assert {:ok, _} = ExTradier.get_order(client, "VA000001", "123456")
    end
  end

  describe "delegate: get_watchlists/1" do
    test "delegates to Watchlist" do
      Req.Test.expect(ExTradierTest.FacadeWatchlists, fn conn ->
        assert conn.request_path == "/v1/watchlists"
        Req.Test.json(conn, Fixtures.watchlists_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeWatchlists)
      assert {:ok, _} = ExTradier.get_watchlists(client)
    end
  end

  describe "delegate: validate_order/1" do
    test "delegates to Trading.validate_order_params" do
      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "market",
        duration: "day"
      }

      assert {:ok, ^params} = ExTradier.validate_order(params)
    end
  end

  describe "delegate: validate_equity_order/1" do
    test "delegates to Trading" do
      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "market",
        duration: "day"
      }

      assert {:ok, _} = ExTradier.validate_equity_order(params)
    end
  end

  describe "delegate: validate_option_order/1" do
    test "delegates to Trading" do
      params = %{
        symbol: "AAPL",
        option_symbol: "AAPL240119C00150000",
        side: "buy_to_open",
        quantity: 1,
        type: "market",
        duration: "day"
      }

      assert {:ok, _} = ExTradier.validate_option_order(params)
    end
  end

  describe "delegate: validate_multileg_order/1" do
    test "delegates to Trading" do
      params = %{
        symbol: "AAPL",
        type: "market",
        duration: "day",
        legs: [
          %{option_symbol: "AAPL240119C00150000", side: "buy_to_open", quantity: 1},
          %{option_symbol: "AAPL240119C00155000", side: "sell_to_open", quantity: 1}
        ]
      }

      assert {:ok, _} = ExTradier.validate_multileg_order(params)
    end
  end

  describe "delegate: valid_equity_sides/0" do
    test "returns valid sides" do
      assert "buy" in ExTradier.valid_equity_sides()
    end
  end

  describe "delegate: valid_option_sides/0" do
    test "returns valid sides" do
      assert "buy_to_open" in ExTradier.valid_option_sides()
    end
  end

  describe "delegate: valid_order_types/0" do
    test "returns valid types" do
      assert "market" in ExTradier.valid_order_types()
    end
  end

  describe "delegate: valid_durations/0" do
    test "returns valid durations" do
      assert "day" in ExTradier.valid_durations()
    end
  end

  describe "create_market_stream/3" do
    test "creates a market streaming session" do
      Req.Test.expect(ExTradierTest.FacadeMarketStream, fn conn ->
        assert conn.request_path == "/v1/markets/events/session"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.streaming_session_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeMarketStream)
      assert {:ok, %{"stream" => _}} = ExTradier.create_market_stream(client, ["AAPL"])
    end
  end

  describe "create_account_stream/2" do
    test "delegates to Streaming.create_account_session" do
      Req.Test.expect(ExTradierTest.FacadeAccountStream, fn conn ->
        assert conn.request_path == "/v1/accounts/events/session"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.account_session_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeAccountStream)
      assert {:ok, %{"stream" => _}} = ExTradier.create_account_stream(client, "VA000001")
    end
  end

  describe "parse_stream_event/1" do
    test "delegates to Streaming.parse_event" do
      json = Jason.encode!(%{"type" => "quote", "symbol" => "AAPL"})
      assert {:ok, %{"type" => "quote"}} = ExTradier.parse_stream_event(json)
    end
  end

  describe "parse_typed_event/1" do
    test "delegates to Streaming" do
      json = Jason.encode!(Fixtures.quote_event())
      assert {:ok, %ExTradier.Streaming.QuoteEvent{}} = ExTradier.parse_typed_event(json)
    end
  end

  describe "delegate: validate_token/1" do
    test "delegates to Client" do
      Req.Test.expect(ExTradierTest.FacadeValidate, fn conn ->
        assert conn.request_path == "/v1/user/profile"
        Req.Test.json(conn, Fixtures.profile_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeValidate)
      assert {:ok, :valid} = ExTradier.validate_token(client)
    end
  end

  describe "delegate: healthcheck/1" do
    test "delegates to Client" do
      Req.Test.expect(ExTradierTest.FacadeHealth, fn conn ->
        Req.Test.json(conn, Fixtures.profile_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeHealth)
      assert :ok = ExTradier.healthcheck(client)
    end
  end

  describe "delegate: post_quotes/2" do
    test "delegates to MarketData" do
      Req.Test.expect(ExTradierTest.FacadePostQuotes, fn conn ->
        assert conn.request_path == "/v1/markets/quotes"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.quotes_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadePostQuotes)
      assert {:ok, _} = ExTradier.post_quotes(client, ["AAPL", "MSFT"])
    end
  end

  describe "delegate: lookup_option_symbols/3" do
    test "delegates to MarketData" do
      Req.Test.expect(ExTradierTest.FacadeOptionLookup, fn conn ->
        assert conn.request_path == "/v1/markets/options/lookup"
        Req.Test.json(conn, Fixtures.option_lookup_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeOptionLookup)
      assert {:ok, _} = ExTradier.lookup_option_symbols(client, "AAPL")
    end
  end

  describe "delegate: place_oto_order/3" do
    test "delegates to Trading" do
      Req.Test.expect(ExTradierTest.FacadeOTO, fn conn ->
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeOTO)
      params = %{symbol: "AAPL", side: "buy", quantity: 100, type: "market", duration: "day"}
      assert {:ok, _} = ExTradier.place_oto_order(client, "VA000001", params)
    end
  end

  describe "delegate: place_oco_order/3" do
    test "delegates to Trading" do
      Req.Test.expect(ExTradierTest.FacadeOCO, fn conn ->
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeOCO)
      params = %{symbol: "AAPL", side: "buy", quantity: 100, type: "market", duration: "day"}
      assert {:ok, _} = ExTradier.place_oco_order(client, "VA000001", params)
    end
  end

  describe "delegate: place_otoco_order/3" do
    test "delegates to Trading" do
      Req.Test.expect(ExTradierTest.FacadeOTOCO, fn conn ->
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeOTOCO)
      params = %{symbol: "AAPL", side: "buy", quantity: 100, type: "market", duration: "day"}
      assert {:ok, _} = ExTradier.place_otoco_order(client, "VA000001", params)
    end
  end

  describe "delegate: get_watchlist/2" do
    test "delegates to Watchlist" do
      Req.Test.expect(ExTradierTest.FacadeGetWl, fn conn ->
        assert conn.request_path == "/v1/watchlists/wl-123"
        Req.Test.json(conn, Fixtures.watchlist_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeGetWl)
      assert {:ok, _} = ExTradier.get_watchlist(client, "wl-123")
    end
  end

  describe "delegate: create_watchlist/2" do
    test "delegates to Watchlist" do
      Req.Test.expect(ExTradierTest.FacadeCreateWl, fn conn ->
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.watchlist_created_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeCreateWl)
      assert {:ok, _} = ExTradier.create_watchlist(client, %{name: "Test"})
    end
  end

  describe "delegate: update_watchlist/3" do
    test "delegates to Watchlist" do
      Req.Test.expect(ExTradierTest.FacadeUpdateWl, fn conn ->
        assert conn.method == "PUT"
        Req.Test.json(conn, Fixtures.watchlist_updated_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeUpdateWl)
      assert {:ok, _} = ExTradier.update_watchlist(client, "wl-123", %{name: "Updated"})
    end
  end

  describe "delegate: delete_watchlist/2" do
    test "delegates to Watchlist" do
      Req.Test.expect(ExTradierTest.FacadeDeleteWl, fn conn ->
        assert conn.method == "DELETE"
        Req.Test.json(conn, Fixtures.watchlist_deleted_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeDeleteWl)
      assert {:ok, _} = ExTradier.delete_watchlist(client, "wl-123")
    end
  end

  describe "delegate: add_watchlist_symbols/3" do
    test "delegates to Watchlist.add_symbols" do
      Req.Test.expect(ExTradierTest.FacadeAddWlSyms, fn conn ->
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.watchlist_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeAddWlSyms)
      assert {:ok, _} = ExTradier.add_watchlist_symbols(client, "wl-123", "GOOG,AMZN")
    end
  end

  describe "delegate: remove_watchlist_symbol/3" do
    test "delegates to Watchlist.remove_symbol" do
      Req.Test.expect(ExTradierTest.FacadeRemoveWlSym, fn conn ->
        assert conn.method == "DELETE"
        Req.Test.json(conn, Fixtures.watchlist_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeRemoveWlSym)
      assert {:ok, _} = ExTradier.remove_watchlist_symbol(client, "wl-123", "GOOG")
    end
  end

  describe "delegate: get_option_greeks/4" do
    test "delegates to MarketData" do
      Req.Test.expect(ExTradierTest.FacadeGreeks, fn conn ->
        assert conn.request_path == "/v1/markets/options/greeks"
        Req.Test.json(conn, Fixtures.option_greeks_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeGreeks)
      assert {:ok, _} = ExTradier.get_option_greeks(client, "AAPL", "2024-01-19")
    end
  end

  describe "delegate: get_option_chains_with_greeks/3" do
    test "delegates to MarketData" do
      Req.Test.expect(ExTradierTest.FacadeChainsGreeks, fn conn ->
        assert conn.request_path == "/v1/markets/options/chains"
        Req.Test.json(conn, Fixtures.option_greeks_response())
      end)

      client = Fixtures.test_client(ExTradierTest.FacadeChainsGreeks)
      assert {:ok, _} = ExTradier.get_option_chains_with_greeks(client, "AAPL")
    end
  end

  describe "delegate: new/2" do
    test "delegates to Client.new" do
      client = ExTradier.new("test_token")
      assert %Req.Request{} = client
    end

    test "passes options through" do
      client = ExTradier.new("test_token", sandbox: false)
      assert %Req.Request{} = client
    end
  end
end
