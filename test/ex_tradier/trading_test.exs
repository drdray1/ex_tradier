defmodule ExTradier.TradingTest do
  use ExUnit.Case, async: true

  alias ExTradier.{Trading, Fixtures}

  describe "place_equity_order/3" do
    test "places an equity order" do
      Req.Test.expect(ExTradier.TradingTest.PlaceOrder, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingTest.PlaceOrder)

      params = %{
        class: "equity",
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "market",
        duration: "day"
      }

      assert {:ok, %{"order" => order}} = Trading.place_equity_order(client, "VA000001", params)
      assert order["status"] == "ok"
    end
  end

  describe "get_orders/3" do
    test "lists orders" do
      Req.Test.expect(ExTradier.TradingTest.GetOrders, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders"
        assert conn.method == "GET"
        Req.Test.json(conn, Fixtures.orders_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingTest.GetOrders)
      assert {:ok, %{"orders" => orders}} = Trading.get_orders(client, "VA000001")
      assert length(orders["order"]) == 2
    end
  end

  describe "cancel_order/3" do
    test "cancels an order" do
      Req.Test.expect(ExTradier.TradingTest.Cancel, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders/123456"
        assert conn.method == "DELETE"
        Req.Test.json(conn, Fixtures.order_cancelled_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingTest.Cancel)
      assert {:ok, _} = Trading.cancel_order(client, "VA000001", "123456")
    end
  end

  describe "validate_order_params/1" do
    test "validates a valid equity order" do
      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "market",
        duration: "day"
      }

      assert {:ok, ^params} = Trading.validate_order_params(params)
    end

    test "returns errors for missing fields" do
      params = %{symbol: "", side: "invalid"}
      assert {:error, errors} = Trading.validate_order_params(params)
      assert is_list(errors)
      assert errors != []
    end

    test "validates price required for limit orders" do
      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "limit",
        duration: "day"
      }

      assert {:error, errors} = Trading.validate_order_params(params)
      assert "price is required for limit orders" in errors
    end
  end

  describe "validate_equity_order/1" do
    test "validates valid equity order" do
      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "market",
        duration: "day"
      }

      assert {:ok, _} = Trading.validate_equity_order(params)
    end

    test "rejects invalid equity side" do
      params = %{
        symbol: "AAPL",
        side: "buy_to_open",
        quantity: 100,
        type: "market",
        duration: "day"
      }

      assert {:error, errors} = Trading.validate_equity_order(params)
      assert Enum.any?(errors, &String.contains?(&1, "side must be one of"))
    end
  end

  describe "validate_option_order/1" do
    test "validates valid option order" do
      params = %{
        symbol: "AAPL",
        option_symbol: "AAPL240119C00150000",
        side: "buy_to_open",
        quantity: 1,
        type: "limit",
        price: 5.00,
        duration: "day"
      }

      assert {:ok, _} = Trading.validate_option_order(params)
    end

    test "rejects invalid OCC format" do
      params = %{
        symbol: "AAPL",
        option_symbol: "INVALID",
        side: "buy_to_open",
        quantity: 1,
        type: "market",
        duration: "day"
      }

      assert {:error, errors} = Trading.validate_option_order(params)
      assert Enum.any?(errors, &String.contains?(&1, "OCC format"))
    end
  end

  describe "validate_multileg_order/1" do
    test "validates valid multi-leg order" do
      params = %{
        symbol: "AAPL",
        type: "market",
        duration: "day",
        legs: [
          %{option_symbol: "AAPL240119C00150000", side: "buy_to_open", quantity: 1},
          %{option_symbol: "AAPL240119C00155000", side: "sell_to_open", quantity: 1}
        ]
      }

      assert {:ok, _} = Trading.validate_multileg_order(params)
    end

    test "rejects single-leg multi-leg order" do
      params = %{
        symbol: "AAPL",
        type: "market",
        duration: "day",
        legs: [
          %{option_symbol: "AAPL240119C00150000", side: "buy_to_open", quantity: 1}
        ]
      }

      assert {:error, errors} = Trading.validate_multileg_order(params)
      assert "multi-leg orders require at least 2 legs" in errors
    end
  end

  describe "valid_* accessors" do
    test "returns valid equity sides" do
      sides = Trading.valid_equity_sides()
      assert "buy" in sides
      assert "sell" in sides
    end

    test "returns valid option sides" do
      sides = Trading.valid_option_sides()
      assert "buy_to_open" in sides
      assert "sell_to_close" in sides
    end

    test "returns valid order types" do
      types = Trading.valid_order_types()
      assert "market" in types
      assert "limit" in types
    end

    test "returns valid durations" do
      durations = Trading.valid_durations()
      assert "day" in durations
      assert "gtc" in durations
    end
  end
end
