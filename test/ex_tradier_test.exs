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
end
