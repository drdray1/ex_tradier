defmodule ExTradier.UserTest do
  use ExUnit.Case, async: true

  alias ExTradier.{User, Fixtures}

  describe "get_profile/1" do
    test "returns user profile" do
      Req.Test.expect(ExTradier.UserTest.Profile, fn conn ->
        assert conn.request_path == "/v1/user/profile"
        Req.Test.json(conn, Fixtures.profile_response())
      end)

      client = Fixtures.test_client(ExTradier.UserTest.Profile)
      assert {:ok, %{"profile" => profile}} = User.get_profile(client)
      assert profile["name"] == "George Costanza"
    end
  end

  describe "get_balances/2" do
    test "returns account balances" do
      Req.Test.expect(ExTradier.UserTest.Balances, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/balances"
        Req.Test.json(conn, Fixtures.balances_response())
      end)

      client = Fixtures.test_client(ExTradier.UserTest.Balances)
      assert {:ok, %{"balances" => balances}} = User.get_balances(client, "VA000001")
      assert balances["total_equity"] == 26_751.69
    end
  end

  describe "get_historical_balances/3" do
    test "returns historical balance data" do
      Req.Test.expect(ExTradier.UserTest.HistoricalBalances, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/balances/historical"
        Req.Test.json(conn, Fixtures.historical_balances_response())
      end)

      client = Fixtures.test_client(ExTradier.UserTest.HistoricalBalances)

      assert {:ok, %{"balances" => balances}} =
               User.get_historical_balances(client, "VA000001")

      assert is_list(balances)
      assert length(balances) == 3
    end

    test "accepts period parameter" do
      Req.Test.expect(ExTradier.UserTest.HistoricalBalancesPeriod, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/balances/historical"
        assert conn.query_string =~ "period=MONTH"
        Req.Test.json(conn, Fixtures.historical_balances_response())
      end)

      client = Fixtures.test_client(ExTradier.UserTest.HistoricalBalancesPeriod)

      assert {:ok, _} =
               User.get_historical_balances(client, "VA000001", %{period: "MONTH"})
    end
  end

  describe "get_positions/2" do
    test "returns account positions" do
      Req.Test.expect(ExTradier.UserTest.Positions, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/positions"
        Req.Test.json(conn, Fixtures.positions_response())
      end)

      client = Fixtures.test_client(ExTradier.UserTest.Positions)
      assert {:ok, %{"positions" => positions}} = User.get_positions(client, "VA000001")
      assert length(positions["position"]) == 2
    end
  end

  describe "get_history/3" do
    test "returns account history" do
      Req.Test.expect(ExTradier.UserTest.History, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/history"
        Req.Test.json(conn, Fixtures.history_response())
      end)

      client = Fixtures.test_client(ExTradier.UserTest.History)
      assert {:ok, %{"history" => _history}} = User.get_history(client, "VA000001")
    end
  end

  describe "get_gainloss/3" do
    test "returns gain/loss data" do
      Req.Test.expect(ExTradier.UserTest.Gainloss, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/gainloss"
        Req.Test.json(conn, Fixtures.gainloss_response())
      end)

      client = Fixtures.test_client(ExTradier.UserTest.Gainloss)
      assert {:ok, %{"gainloss" => _}} = User.get_gainloss(client, "VA000001")
    end
  end

  describe "get_cost_basis/3" do
    test "returns cost basis for symbol" do
      Req.Test.expect(ExTradier.UserTest.CostBasis, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/costbasis"
        Req.Test.json(conn, Fixtures.cost_basis_response())
      end)

      client = Fixtures.test_client(ExTradier.UserTest.CostBasis)
      assert {:ok, %{"costbasis" => _}} = User.get_cost_basis(client, "VA000001", "AAPL")
    end
  end
end
