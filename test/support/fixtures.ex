defmodule ExTradier.Fixtures do
  @moduledoc """
  Test fixtures and helpers for ExTradier tests.
  """

  @doc """
  Creates a test client with Req.Test plug for HTTP mocking.
  """
  def test_client(stub_name) do
    ExTradier.Client.new("test_token", plug: {Req.Test, stub_name})
  end

  # ============================================================================
  # User/Profile responses
  # ============================================================================

  def profile_response do
    %{
      "profile" => %{
        "id" => "id-gcostanza",
        "name" => "George Costanza",
        "account" => [
          %{
            "account_number" => "VA000001",
            "classification" => "individual",
            "date_created" => "2016-08-01T21:08:55.000Z",
            "day_trader" => false,
            "option_level" => 6,
            "status" => "active",
            "type" => "margin",
            "last_update_date" => "2016-08-01T21:08:55.000Z"
          },
          %{
            "account_number" => "VA000002",
            "classification" => "individual",
            "date_created" => "2016-08-02T21:08:55.000Z",
            "day_trader" => false,
            "option_level" => 2,
            "status" => "active",
            "type" => "cash",
            "last_update_date" => "2016-08-02T21:08:55.000Z"
          }
        ]
      }
    }
  end

  def profile_single_account_response do
    %{
      "profile" => %{
        "id" => "id-gcostanza",
        "name" => "George Costanza",
        "account" => %{
          "account_number" => "VA000001",
          "classification" => "individual",
          "date_created" => "2016-08-01T21:08:55.000Z",
          "day_trader" => false,
          "option_level" => 6,
          "status" => "active",
          "type" => "margin",
          "last_update_date" => "2016-08-01T21:08:55.000Z"
        }
      }
    }
  end

  # ============================================================================
  # Balance responses
  # ============================================================================

  def balances_response do
    %{
      "balances" => %{
        "option_short_value" => 0,
        "total_equity" => 26_751.69,
        "account_number" => "VA000001",
        "account_type" => "margin",
        "close_pl" => 0,
        "current_requirement" => 6432.0,
        "long_market_value" => 16_084.0,
        "market_value" => 16_084.0,
        "open_pl" => -1760.0,
        "total_cash" => 10_667.69,
        "margin" => %{
          "fed_call" => 0,
          "maintenance_call" => 0,
          "option_buying_power" => 10_667.69,
          "stock_buying_power" => 21_335.38
        }
      }
    }
  end

  # ============================================================================
  # Position responses
  # ============================================================================

  def positions_response do
    %{
      "positions" => %{
        "position" => [
          %{
            "cost_basis" => 207.01,
            "date_acquired" => "2019-01-31T00:00:00.000Z",
            "id" => 130_089,
            "quantity" => 1.0,
            "symbol" => "AAPL"
          },
          %{
            "cost_basis" => 1870.70,
            "date_acquired" => "2019-01-31T00:00:00.000Z",
            "id" => 130_090,
            "quantity" => 10.0,
            "symbol" => "MSFT"
          }
        ]
      }
    }
  end

  def positions_empty_response do
    %{"positions" => "null"}
  end

  # ============================================================================
  # Quote responses
  # ============================================================================

  def quote_response(symbol \\ "AAPL") do
    %{
      "quotes" => %{
        "quote" => %{
          "symbol" => symbol,
          "description" => "Apple Inc",
          "last" => 150.25,
          "change" => 1.25,
          "volume" => 45_123_456,
          "open" => 149.50,
          "high" => 151.00,
          "low" => 149.25,
          "bid" => 150.20,
          "ask" => 150.30,
          "prevclose" => 149.00
        }
      }
    }
  end

  def quotes_response do
    %{
      "quotes" => %{
        "quote" => [
          %{"symbol" => "AAPL", "last" => 150.25, "bid" => 150.20, "ask" => 150.30},
          %{"symbol" => "MSFT", "last" => 380.50, "bid" => 380.45, "ask" => 380.55}
        ]
      }
    }
  end

  # ============================================================================
  # Historical data responses
  # ============================================================================

  def historical_response do
    %{
      "history" => %{
        "day" => [
          %{
            "date" => "2024-01-02",
            "open" => 149.50,
            "high" => 151.00,
            "low" => 149.25,
            "close" => 150.25,
            "volume" => 45_123_456
          },
          %{
            "date" => "2024-01-03",
            "open" => 150.25,
            "high" => 152.00,
            "low" => 149.50,
            "close" => 151.75,
            "volume" => 48_456_789
          }
        ]
      }
    }
  end

  def timesales_response do
    %{
      "series" => %{
        "data" => [
          %{
            "time" => "2024-01-02T09:30:00",
            "price" => 149.50,
            "volume" => 125_000
          }
        ]
      }
    }
  end

  # ============================================================================
  # Options responses
  # ============================================================================

  def option_chains_response do
    %{
      "options" => %{
        "option" => [
          %{
            "symbol" => "AAPL240119C00150000",
            "description" => "AAPL Jan 19 2024 $150.00 Call",
            "last" => 5.25,
            "bid" => 5.20,
            "ask" => 5.30,
            "strike" => 150.0,
            "option_type" => "call"
          },
          %{
            "symbol" => "AAPL240119P00150000",
            "description" => "AAPL Jan 19 2024 $150.00 Put",
            "last" => 4.75,
            "bid" => 4.70,
            "ask" => 4.80,
            "strike" => 150.0,
            "option_type" => "put"
          }
        ]
      }
    }
  end

  def option_expirations_response do
    %{
      "expirations" => %{
        "date" => ["2024-01-19", "2024-01-26", "2024-02-02"]
      }
    }
  end

  def option_strikes_response do
    %{
      "strikes" => %{
        "strike" => [145.0, 147.5, 150.0, 152.5, 155.0]
      }
    }
  end

  # ============================================================================
  # Order responses
  # ============================================================================

  def order_placed_response do
    %{"order" => %{"id" => 123_458, "status" => "ok"}}
  end

  def order_response do
    %{
      "order" => %{
        "id" => 123_456,
        "type" => "market",
        "symbol" => "AAPL",
        "side" => "buy",
        "quantity" => 100.0,
        "status" => "filled",
        "class" => "equity"
      }
    }
  end

  def orders_response do
    %{
      "orders" => %{
        "order" => [
          %{"id" => 123_456, "symbol" => "AAPL", "status" => "filled"},
          %{"id" => 123_457, "symbol" => "MSFT", "status" => "pending"}
        ]
      }
    }
  end

  def order_modified_response do
    %{"order" => %{"id" => 123_456, "status" => "ok"}}
  end

  def order_cancelled_response do
    %{"order" => %{"id" => 123_456, "status" => "ok"}}
  end

  def order_preview_response do
    %{
      "order" => %{
        "cost" => 15_025.00,
        "commission" => 0.00,
        "fees" => 0.13
      }
    }
  end

  # ============================================================================
  # Account history responses
  # ============================================================================

  def history_response do
    %{
      "history" => %{
        "event" => [
          %{
            "amount" => 15_025.00,
            "date" => "2024-01-02T00:00:00.000Z",
            "type" => "trade"
          }
        ]
      }
    }
  end

  def gainloss_response do
    %{
      "gainloss" => %{
        "closed_position" => [
          %{
            "symbol" => "AAPL",
            "gain_loss" => 1025.00,
            "gain_loss_percent" => 7.32
          }
        ]
      }
    }
  end

  # ============================================================================
  # Market clock/calendar responses
  # ============================================================================

  def clock_response do
    %{
      "clock" => %{
        "date" => "2024-01-02",
        "state" => "open",
        "timestamp" => 1_704_214_800
      }
    }
  end

  def calendar_response do
    %{
      "calendar" => %{
        "month" => 1,
        "year" => 2024,
        "days" => %{
          "day" => [
            %{"date" => "2024-01-02", "status" => "open"},
            %{"date" => "2024-01-03", "status" => "open"}
          ]
        }
      }
    }
  end

  # ============================================================================
  # Watchlist responses
  # ============================================================================

  def watchlists_response do
    %{
      "watchlists" => %{
        "watchlist" => [
          %{"name" => "Tech Stocks", "id" => "wl-tech-123"},
          %{"name" => "Dividend Stocks", "id" => "wl-div-456"}
        ]
      }
    }
  end

  def watchlist_response do
    %{
      "watchlist" => %{
        "name" => "Tech Stocks",
        "id" => "wl-tech-123",
        "items" => %{
          "item" => [
            %{"symbol" => "AAPL", "id" => "item-1"},
            %{"symbol" => "MSFT", "id" => "item-2"}
          ]
        }
      }
    }
  end

  def watchlist_created_response do
    %{"watchlist" => %{"name" => "New Watchlist", "id" => "wl-new-789"}}
  end

  def watchlist_updated_response do
    %{"watchlist" => %{"name" => "Updated Watchlist", "id" => "wl-tech-123"}}
  end

  def watchlist_deleted_response do
    %{"watchlists" => %{}}
  end

  # ============================================================================
  # Streaming session responses
  # ============================================================================

  def streaming_session_response do
    %{
      "stream" => %{
        "sessionid" => "session-abc123def456",
        "url" => "wss://stream.tradier.com/v1/markets/events"
      }
    }
  end

  def account_session_response do
    %{
      "stream" => %{
        "sessionid" => "account-session-xyz789",
        "url" => "wss://stream.tradier.com/v1/accounts/events"
      }
    }
  end

  # ============================================================================
  # Streaming event fixtures
  # ============================================================================

  def quote_event do
    %{
      "type" => "quote",
      "symbol" => "AAPL",
      "bid" => 150.20,
      "bidsz" => 2,
      "bidexch" => "Q",
      "biddate" => "1705084800000",
      "ask" => 150.30,
      "asksz" => 3,
      "askexch" => "P",
      "askdate" => "1705084800000"
    }
  end

  def trade_event do
    %{
      "type" => "trade",
      "symbol" => "AAPL",
      "exch" => "Q",
      "price" => "150.25",
      "size" => "100",
      "cvol" => "45123456",
      "date" => "1705084800000",
      "last" => "150.25"
    }
  end

  def summary_event do
    %{
      "type" => "summary",
      "symbol" => "AAPL",
      "open" => "149.50",
      "high" => "151.00",
      "low" => "149.25",
      "prevClose" => "149.00"
    }
  end

  def timesale_event do
    %{
      "type" => "timesale",
      "symbol" => "AAPL",
      "exch" => "Q",
      "bid" => "150.20",
      "ask" => "150.30",
      "last" => "150.25",
      "size" => "100",
      "date" => "1705084800000"
    }
  end
end
