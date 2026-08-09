defmodule ExTradier.TradingTest do
  use ExUnit.Case, async: true

  alias ExTradier.{Fixtures, Trading}

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

  describe "place_option_order/3" do
    test "places an option order" do
      Req.Test.expect(ExTradier.TradingTest.PlaceOption, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingTest.PlaceOption)

      params = %{
        symbol: "AAPL",
        option_symbol: "AAPL240119C00150000",
        side: "buy_to_open",
        quantity: 1,
        type: "limit",
        price: 5.00,
        duration: "day"
      }

      assert {:ok, %{"order" => order}} = Trading.place_option_order(client, "VA000001", params)
      assert order["status"] == "ok"
    end
  end

  describe "place_multileg_order/3" do
    test "places a multi-leg order" do
      Req.Test.expect(ExTradier.TradingTest.PlaceMultileg, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingTest.PlaceMultileg)

      params = %{
        symbol: "AAPL",
        type: "market",
        duration: "day",
        legs: [
          %{option_symbol: "AAPL240119C00150000", side: "buy_to_open", quantity: 1},
          %{option_symbol: "AAPL240119C00155000", side: "sell_to_open", quantity: 1}
        ]
      }

      assert {:ok, %{"order" => order}} =
               Trading.place_multileg_order(client, "VA000001", params)

      assert order["status"] == "ok"
    end
  end

  describe "place_combo_order/3" do
    test "places a combo order" do
      Req.Test.expect(ExTradier.TradingTest.PlaceCombo, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingTest.PlaceCombo)

      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "market",
        duration: "day"
      }

      assert {:ok, %{"order" => _}} = Trading.place_combo_order(client, "VA000001", params)
    end
  end

  describe "modify_order/4" do
    test "modifies an order" do
      Req.Test.expect(ExTradier.TradingTest.Modify, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders/123456"
        assert conn.method == "PUT"
        Req.Test.json(conn, Fixtures.order_modified_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingTest.Modify)

      assert {:ok, %{"order" => order}} =
               Trading.modify_order(client, "VA000001", "123456", %{type: "limit", price: 155.00})

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

  describe "get_order/3" do
    test "gets a specific order" do
      Req.Test.expect(ExTradier.TradingTest.GetOrder, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders/123456"
        assert conn.method == "GET"
        Req.Test.json(conn, Fixtures.order_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingTest.GetOrder)
      assert {:ok, %{"order" => order}} = Trading.get_order(client, "VA000001", "123456")
      assert order["id"] == 123_456
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

  describe "preview_order/3" do
    test "previews an order" do
      Req.Test.expect(ExTradier.TradingTest.Preview, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.order_preview_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingTest.Preview)

      params = %{
        class: "equity",
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "market",
        duration: "day"
      }

      assert {:ok, %{"order" => preview}} = Trading.preview_order(client, "VA000001", params)
      assert preview["commission"] == 0.00
    end
  end

  describe "place_oto_order/3" do
    test "places an OTO order" do
      Req.Test.expect(ExTradier.TradingTest.PlaceOTO, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingTest.PlaceOTO)
      params = %{symbol: "AAPL", side: "buy", quantity: 100, type: "market", duration: "day"}
      assert {:ok, %{"order" => _}} = Trading.place_oto_order(client, "VA000001", params)
    end
  end

  describe "place_oco_order/3" do
    test "places an OCO order" do
      Req.Test.expect(ExTradier.TradingTest.PlaceOCO, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingTest.PlaceOCO)
      params = %{symbol: "AAPL", side: "buy", quantity: 100, type: "market", duration: "day"}
      assert {:ok, %{"order" => _}} = Trading.place_oco_order(client, "VA000001", params)
    end
  end

  describe "place_otoco_order/3" do
    test "places an OTOCO order" do
      Req.Test.expect(ExTradier.TradingTest.PlaceOTOCO, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingTest.PlaceOTOCO)
      params = %{symbol: "AAPL", side: "buy", quantity: 100, type: "market", duration: "day"}
      assert {:ok, %{"order" => _}} = Trading.place_otoco_order(client, "VA000001", params)
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

    test "returns valid order classes" do
      classes = Trading.valid_order_classes()
      assert "equity" in classes
      assert "option" in classes
      assert "multileg" in classes
      assert "combo" in classes
      assert "oto" in classes
      assert "oco" in classes
      assert "otoco" in classes
    end
  end

  describe "validate_order_params/1 edge cases" do
    test "returns error for non-map params" do
      assert {:error, ["params must be a map"]} = Trading.validate_order_params("invalid")
    end

    test "returns error for invalid order type" do
      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "invalid_type",
        duration: "day"
      }

      assert {:error, errors} = Trading.validate_order_params(params)
      assert Enum.any?(errors, &String.contains?(&1, "type must be one of"))
    end

    test "returns error for invalid duration" do
      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "market",
        duration: "invalid"
      }

      assert {:error, errors} = Trading.validate_order_params(params)
      assert Enum.any?(errors, &String.contains?(&1, "duration must be one of"))
    end

    test "returns error for non-positive quantity" do
      params = %{symbol: "AAPL", side: "buy", quantity: -1, type: "market", duration: "day"}
      assert {:error, errors} = Trading.validate_order_params(params)
      assert "quantity must be a positive number" in errors
    end

    test "returns error for zero quantity" do
      params = %{symbol: "AAPL", side: "buy", quantity: 0, type: "market", duration: "day"}
      assert {:error, errors} = Trading.validate_order_params(params)
      assert "quantity must be a positive number" in errors
    end

    test "validates stop required for stop orders" do
      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "stop",
        duration: "day"
      }

      assert {:error, errors} = Trading.validate_order_params(params)
      assert "stop is required for stop orders" in errors
    end

    test "validates stop positive for stop orders" do
      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "stop",
        duration: "day",
        stop: -5
      }

      assert {:error, errors} = Trading.validate_order_params(params)
      assert "stop must be a positive number" in errors
    end

    test "validates price positive for limit orders" do
      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "limit",
        duration: "day",
        price: -1
      }

      assert {:error, errors} = Trading.validate_order_params(params)
      assert "price must be a positive number" in errors
    end
  end

  describe "validate_equity_order/1 edge cases" do
    test "returns error for non-map params" do
      assert {:error, ["params must be a map"]} = Trading.validate_equity_order("invalid")
    end
  end

  describe "validate_option_order/1 edge cases" do
    test "returns error for non-map params" do
      assert {:error, ["params must be a map"]} = Trading.validate_option_order("invalid")
    end
  end

  describe "validate_multileg_order/1 edge cases" do
    test "returns error for non-map params" do
      assert {:error, ["params must be a map"]} = Trading.validate_multileg_order("invalid")
    end

    test "returns error for >4 legs" do
      params = %{
        symbol: "AAPL",
        type: "market",
        duration: "day",
        legs: [
          %{option_symbol: "AAPL240119C00150000", side: "buy_to_open", quantity: 1},
          %{option_symbol: "AAPL240119C00155000", side: "sell_to_open", quantity: 1},
          %{option_symbol: "AAPL240119P00150000", side: "buy_to_open", quantity: 1},
          %{option_symbol: "AAPL240119P00155000", side: "sell_to_open", quantity: 1},
          %{option_symbol: "AAPL240119P00160000", side: "sell_to_open", quantity: 1}
        ]
      }

      assert {:error, errors} = Trading.validate_multileg_order(params)
      assert "multi-leg orders cannot exceed 4 legs" in errors
    end

    test "returns error for non-list legs" do
      params = %{
        symbol: "AAPL",
        type: "market",
        duration: "day",
        legs: "not a list"
      }

      assert {:error, errors} = Trading.validate_multileg_order(params)
      assert "legs must be a list" in errors
    end

    test "returns error for non-map leg" do
      params = %{
        symbol: "AAPL",
        type: "market",
        duration: "day",
        legs: ["not a map", "also not a map"]
      }

      assert {:error, errors} = Trading.validate_multileg_order(params)
      assert Enum.any?(errors, &String.contains?(&1, "must be a map"))
    end

    test "returns error for leg with invalid side" do
      params = %{
        symbol: "AAPL",
        type: "market",
        duration: "day",
        legs: [
          %{option_symbol: "AAPL240119C00150000", side: "invalid", quantity: 1},
          %{option_symbol: "AAPL240119C00155000", side: "sell_to_open", quantity: 1}
        ]
      }

      assert {:error, errors} = Trading.validate_multileg_order(params)
      assert Enum.any?(errors, &String.contains?(&1, "side must be one of"))
    end

    test "returns error for leg with missing fields" do
      params = %{
        symbol: "AAPL",
        type: "market",
        duration: "day",
        legs: [
          %{},
          %{option_symbol: "AAPL240119C00155000", side: "sell_to_open", quantity: 1}
        ]
      }

      assert {:error, errors} = Trading.validate_multileg_order(params)
      assert Enum.any?(errors, &String.contains?(&1, "option_symbol is required"))
    end

    test "returns error for leg with non-positive quantity" do
      params = %{
        symbol: "AAPL",
        type: "market",
        duration: "day",
        legs: [
          %{option_symbol: "AAPL240119C00150000", side: "buy_to_open", quantity: -1},
          %{option_symbol: "AAPL240119C00155000", side: "sell_to_open", quantity: 1}
        ]
      }

      assert {:error, errors} = Trading.validate_multileg_order(params)
      assert Enum.any?(errors, &String.contains?(&1, "quantity must be a positive number"))
    end
  end

  describe "validate_option_order/1 symbol format" do
    test "rejects too-long root symbol" do
      params = %{
        symbol: "ABCDEFG",
        option_symbol: "ABCDEFG240119C00150000",
        side: "buy_to_open",
        quantity: 1,
        type: "market",
        duration: "day"
      }

      assert {:error, errors} = Trading.validate_option_order(params)
      assert Enum.any?(errors, &String.contains?(&1, "OCC format"))
    end
  end

  describe "validate_option_side/2" do
    test "rejects equity side for option orders" do
      params = %{
        symbol: "AAPL",
        option_symbol: "AAPL240119C00150000",
        side: "buy",
        quantity: 1,
        type: "market",
        duration: "day"
      }

      assert {:error, errors} = Trading.validate_option_order(params)
      assert Enum.any?(errors, &String.contains?(&1, "side must be one of"))
    end
  end

  describe "validate_oco_order/1" do
    test "accepts OCO with different order types" do
      params = %{"type[0]" => "limit", "type[1]" => "stop"}
      assert {:ok, _} = Trading.validate_oco_order(params)
    end

    test "rejects OCO with same order types" do
      params = %{"type[0]" => "limit", "type[1]" => "limit"}
      assert {:error, errors} = Trading.validate_oco_order(params)
      assert "OCO legs must have different order types" in errors
    end

    test "accepts OCO when types are not both specified" do
      params = %{"type[0]" => "limit"}
      assert {:ok, _} = Trading.validate_oco_order(params)
    end

    test "rejects non-map params" do
      assert {:error, ["params must be a map"]} = Trading.validate_oco_order("invalid")
    end
  end

  describe "validate_otoco_order/1" do
    test "accepts OTOCO with matching symbols and different types" do
      params = %{
        "symbol[1]" => "AAPL",
        "symbol[2]" => "AAPL",
        "type[1]" => "limit",
        "type[2]" => "stop"
      }

      assert {:ok, _} = Trading.validate_otoco_order(params)
    end

    test "rejects OTOCO with mismatched symbols on legs 2 and 3" do
      params = %{"symbol[1]" => "AAPL", "symbol[2]" => "MSFT"}
      assert {:error, errors} = Trading.validate_otoco_order(params)
      assert "OTOCO legs 2 and 3 must have the same symbol" in errors
    end

    test "rejects OTOCO with same order types on legs 2 and 3" do
      params = %{
        "symbol[1]" => "AAPL",
        "symbol[2]" => "AAPL",
        "type[1]" => "limit",
        "type[2]" => "limit"
      }

      assert {:error, errors} = Trading.validate_otoco_order(params)
      assert "OTOCO legs 2 and 3 must have different order types" in errors
    end

    test "accepts OTOCO when optional fields are absent" do
      params = %{}
      assert {:ok, _} = Trading.validate_otoco_order(params)
    end

    test "rejects non-map params" do
      assert {:error, ["params must be a map"]} = Trading.validate_otoco_order("invalid")
    end
  end

  describe "tag validation" do
    test "accepts valid tag in order params" do
      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "market",
        duration: "day",
        tag: "my-custom-tag"
      }

      assert {:ok, _} = Trading.validate_order_params(params)
    end

    test "accepts order without tag" do
      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "market",
        duration: "day"
      }

      assert {:ok, _} = Trading.validate_order_params(params)
    end

    test "rejects non-string tag" do
      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "market",
        duration: "day",
        tag: 123
      }

      assert {:error, errors} = Trading.validate_order_params(params)
      assert "tag must be a string" in errors
    end

    test "rejects tag longer than 255 characters" do
      params = %{
        symbol: "AAPL",
        side: "buy",
        quantity: 100,
        type: "market",
        duration: "day",
        tag: String.duplicate("a", 256)
      }

      assert {:error, errors} = Trading.validate_order_params(params)
      assert "tag must be 255 characters or fewer" in errors
    end
  end
end
