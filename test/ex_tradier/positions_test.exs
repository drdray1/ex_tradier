defmodule ExTradier.PositionsTest do
  use ExUnit.Case, async: true

  alias ExTradier.{Fixtures, Positions}

  describe "get_position_groups/2" do
    test "returns all position groups" do
      Req.Test.expect(ExTradier.PositionsTest.List, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/position_groups"
        assert conn.method == "GET"
        Req.Test.json(conn, Fixtures.position_groups_response())
      end)

      client = Fixtures.test_client(ExTradier.PositionsTest.List)

      assert {:ok, %{"position_groups" => groups}} =
               Positions.get_position_groups(client, "VA000001")

      assert length(groups) == 2
    end
  end

  describe "create_position_group/3" do
    test "creates a position group" do
      Req.Test.expect(ExTradier.PositionsTest.Create, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/position_groups"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.position_group_created_response())
      end)

      client = Fixtures.test_client(ExTradier.PositionsTest.Create)

      assert {:ok, %{"position_group" => group}} =
               Positions.create_position_group(client, "VA000001", %{
                 name: "New Group",
                 symbols: "AAPL"
               })

      assert group["name"] == "New Group"
    end
  end

  describe "update_position_group/4" do
    test "updates a position group" do
      Req.Test.expect(ExTradier.PositionsTest.Update, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/position_groups/pg-123"
        assert conn.method == "PUT"
        Req.Test.json(conn, Fixtures.position_group_updated_response())
      end)

      client = Fixtures.test_client(ExTradier.PositionsTest.Update)

      assert {:ok, %{"position_group" => group}} =
               Positions.update_position_group(client, "VA000001", "pg-123", %{
                 name: "Updated Group"
               })

      assert group["name"] == "Updated Group"
    end
  end

  describe "delete_position_group/3" do
    test "deletes a position group" do
      Req.Test.expect(ExTradier.PositionsTest.Delete, fn conn ->
        assert conn.request_path == "/v1/accounts/VA000001/position_groups/pg-123"
        assert conn.method == "DELETE"
        Req.Test.json(conn, Fixtures.position_group_deleted_response())
      end)

      client = Fixtures.test_client(ExTradier.PositionsTest.Delete)
      assert {:ok, _} = Positions.delete_position_group(client, "VA000001", "pg-123")
    end
  end
end
