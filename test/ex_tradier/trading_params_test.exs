defmodule ExTradier.TradingParamsTest do
  @moduledoc """
  Covers the order parameters Tradier documents, including the net-priced
  `market`/`debit`/`credit`/`even` types that multi-leg orders use instead of
  the single-leg `limit`/`stop` types.
  """
  use ExUnit.Case, async: true

  alias ExTradier.{Fixtures, Trading}

  describe "validate_multileg_order/1 types" do
    defp multileg(overrides) do
      Map.merge(
        %{
          symbol: "AAPL",
          type: "market",
          duration: "day",
          legs: [
            %{option_symbol: "AAPL240119C00150000", side: "buy_to_open", quantity: 1},
            %{option_symbol: "AAPL240119C00155000", side: "sell_to_open", quantity: 1}
          ]
        },
        overrides
      )
    end

    test "accepts every documented multi-leg type" do
      for type <- ~w(market even) do
        assert {:ok, _} = Trading.validate_multileg_order(multileg(%{type: type}))
      end

      for type <- ~w(debit credit) do
        assert {:ok, _} = Trading.validate_multileg_order(multileg(%{type: type, price: 1.25}))
      end
    end

    test "rejects single-leg order types" do
      for type <- ~w(limit stop stop_limit) do
        assert {:error, errors} = Trading.validate_multileg_order(multileg(%{type: type}))
        assert "type must be one of: market, debit, credit, even" in errors
      end
    end

    test "requires a price for debit and credit spreads" do
      for type <- ~w(debit credit) do
        assert {:error, errors} = Trading.validate_multileg_order(multileg(%{type: type}))
        assert "price is required for #{type} orders" in errors
      end
    end

    test "does not require a price for market or even spreads" do
      for type <- ~w(market even) do
        assert {:ok, _} = Trading.validate_multileg_order(multileg(%{type: type}))
      end
    end

    test "rejects a non-positive price" do
      assert {:error, errors} =
               Trading.validate_multileg_order(multileg(%{type: "debit", price: 0}))

      assert "price must be a positive number" in errors
    end
  end

  describe "valid_multileg_types/0" do
    test "returns the net-priced order types" do
      assert Trading.valid_multileg_types() == ["market", "debit", "credit", "even"]
    end

    test "single-leg types are unchanged" do
      assert Trading.valid_order_types() == ["market", "limit", "stop", "stop_limit"]
    end
  end

  describe "order class handling" do
    test "place_option_order/3 sets class=option without mutating other params" do
      Req.Test.expect(ExTradier.TradingParamsTest.Option, fn conn ->
        assert conn.body_params["class"] == "option"
        assert conn.body_params["option_symbol"] == "AAPL240119C00150000"

        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingParamsTest.Option)

      assert {:ok, _} =
               Trading.place_option_order(client, "VA000001", %{
                 symbol: "AAPL",
                 option_symbol: "AAPL240119C00150000",
                 side: "buy_to_open",
                 quantity: 1,
                 type: "market",
                 duration: "day"
               })
    end

    test "a caller-supplied class cannot override the class the function implies" do
      Req.Test.expect(ExTradier.TradingParamsTest.ClassOverride, fn conn ->
        assert conn.body_params["class"] == "oco"

        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingParamsTest.ClassOverride)

      assert {:ok, _} =
               Trading.place_oco_order(client, "VA000001", %{class: "equity", duration: "day"})
    end

    test "accepts a keyword list of params" do
      Req.Test.expect(ExTradier.TradingParamsTest.Keyword, fn conn ->
        assert conn.body_params["symbol"] == "AAPL"
        assert conn.body_params["quantity"] == "100"

        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingParamsTest.Keyword)

      assert {:ok, _} =
               Trading.place_equity_order(client, "VA000001",
                 symbol: "AAPL",
                 side: "buy",
                 quantity: 100,
                 type: "market",
                 duration: "day"
               )
    end

    test "drops nil params rather than sending empty strings" do
      Req.Test.expect(ExTradier.TradingParamsTest.Nils, fn conn ->
        refute Map.has_key?(conn.body_params, "price")
        refute Map.has_key?(conn.body_params, "stop")

        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingParamsTest.Nils)

      assert {:ok, _} =
               Trading.place_equity_order(client, "VA000001", %{
                 symbol: "AAPL",
                 side: "buy",
                 quantity: 100,
                 type: "market",
                 duration: "day",
                 price: nil,
                 stop: nil
               })
    end
  end

  describe "place_multileg_order/3" do
    test "expands legs into indexed form fields" do
      Req.Test.expect(ExTradier.TradingParamsTest.Multileg, fn conn ->
        # Plug decodes Tradier's indexed `option_symbol[0]` fields into nested maps
        assert conn.body_params["class"] == "multileg"

        assert conn.body_params["option_symbol"] == %{
                 "0" => "AAPL240119C00150000",
                 "1" => "AAPL240119C00155000"
               }

        assert conn.body_params["side"] == %{"0" => "buy_to_open", "1" => "sell_to_open"}
        assert conn.body_params["quantity"] == %{"0" => "1", "1" => "1"}
        refute Map.has_key?(conn.body_params, "legs")

        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingParamsTest.Multileg)

      assert {:ok, _} =
               Trading.place_multileg_order(client, "VA000001", %{
                 symbol: "AAPL",
                 type: "debit",
                 duration: "day",
                 price: 1.25,
                 legs: [
                   %{option_symbol: "AAPL240119C00150000", side: "buy_to_open", quantity: 1},
                   %{option_symbol: "AAPL240119C00155000", side: "sell_to_open", quantity: 1}
                 ]
               })
    end

    test "accepts params that already use indexed keys" do
      Req.Test.expect(ExTradier.TradingParamsTest.MultilegIndexed, fn conn ->
        assert conn.body_params["class"] == "multileg"
        assert conn.body_params["option_symbol"] == %{"0" => "AAPL240119C00150000"}

        Req.Test.json(conn, Fixtures.order_placed_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingParamsTest.MultilegIndexed)

      assert {:ok, _} =
               Trading.place_multileg_order(client, "VA000001", %{
                 "symbol" => "AAPL",
                 "type" => "even",
                 "duration" => "day",
                 "option_symbol[0]" => "AAPL240119C00150000",
                 "side[0]" => "buy_to_open",
                 "quantity[0]" => 1
               })
    end
  end

  describe "preview_order/3" do
    test "forces preview=true even if the caller passed false" do
      Req.Test.expect(ExTradier.TradingParamsTest.Preview, fn conn ->
        assert conn.body_params["preview"] == "true"

        Req.Test.json(conn, Fixtures.order_preview_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingParamsTest.Preview)

      assert {:ok, _} =
               Trading.preview_order(client, "VA000001", %{
                 class: "equity",
                 symbol: "AAPL",
                 side: "buy",
                 quantity: 100,
                 type: "market",
                 duration: "day",
                 preview: false
               })
    end
  end

  describe "get_orders/3 and get_order/4" do
    test "forwards pagination and tag params" do
      Req.Test.expect(ExTradier.TradingParamsTest.Orders, fn conn ->
        params = URI.decode_query(conn.query_string)

        assert params["page"] == "2"
        assert params["limit"] == "100"
        assert params["includeTags"] == "true"
        assert params["status"] == "open,filled"

        Req.Test.json(conn, Fixtures.orders_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingParamsTest.Orders)

      assert {:ok, _} =
               Trading.get_orders(client, "VA000001",
                 page: 2,
                 limit: 100,
                 includeTags: true,
                 status: "open,filled"
               )
    end

    test "get_order/4 forwards includeTags" do
      Req.Test.expect(ExTradier.TradingParamsTest.Order, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/orders/123456"
        assert URI.decode_query(conn.query_string)["includeTags"] == "true"

        Req.Test.json(conn, Fixtures.order_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingParamsTest.Order)
      assert {:ok, _} = Trading.get_order(client, "VA000001", 123_456, includeTags: true)
    end

    test "get_order/3 still works without params" do
      Req.Test.expect(ExTradier.TradingParamsTest.OrderBare, fn conn ->
        assert conn.query_string == ""

        Req.Test.json(conn, Fixtures.order_response())
      end)

      client = Fixtures.test_client(ExTradier.TradingParamsTest.OrderBare)
      assert {:ok, _} = Trading.get_order(client, "VA000001", 123_456)
    end
  end
end
