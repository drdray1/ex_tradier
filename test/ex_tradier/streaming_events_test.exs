defmodule ExTradier.StreamingEventsTest do
  @moduledoc """
  Covers the streaming event fields Tradier documents that the typed structs
  previously dropped, plus the account event stream.
  """
  use ExUnit.Case, async: true

  alias ExTradier.Fixtures
  alias ExTradier.Streaming
  alias ExTradier.Streaming.{HeartbeatEvent, OrderEvent, TimesaleEvent}

  doctest ExTradier.Streaming, only: [parse_account_event: 1]

  describe "timesale events" do
    test "parses the sequence, flag, cancel, correction and session fields" do
      assert %TimesaleEvent{
               symbol: "AAPL",
               seq: 352_795,
               flag: "",
               cancel: false,
               correction: false,
               session: "normal"
             } = Streaming.parse_timesale_event(Fixtures.timesale_event())
    end

    test "flags a cancelled print so volume calculations can exclude it" do
      event =
        Fixtures.timesale_event()
        |> Map.merge(%{"cancel" => true, "correction" => true, "session" => "pre"})
        |> Streaming.parse_timesale_event()

      assert event.cancel == true
      assert event.correction == true
      assert event.session == "pre"
    end

    test "parses string booleans, which Tradier sends for some fields" do
      event =
        Fixtures.timesale_event()
        |> Map.merge(%{"cancel" => "true", "correction" => "false"})
        |> Streaming.parse_timesale_event()

      assert event.cancel == true
      assert event.correction == false
    end

    test "leaves the new fields nil when absent" do
      event =
        Streaming.parse_timesale_event(%{
          "type" => "timesale",
          "symbol" => "AAPL",
          "last" => "150.25"
        })

      assert event.seq == nil
      assert event.cancel == nil
      assert event.session == nil
      assert event.last == 150.25
    end

    test "still routes through parse_typed_event/1" do
      json = Jason.encode!(Fixtures.timesale_event())

      assert {:ok, %TimesaleEvent{seq: 352_795}} = Streaming.parse_typed_event(json)
    end
  end

  describe "parse_account_event/1" do
    test "parses an order event into a struct with parsed timestamps" do
      json = Jason.encode!(Fixtures.order_event())

      assert {:ok, event} = Streaming.parse_account_event(json)

      assert %OrderEvent{
               id: 1_107_075,
               account: "6YA",
               status: "open",
               type: "limit",
               price: 10.0,
               remaining_quantity: 2.0
             } = event

      assert event.stop_price == 0.0
      assert event.exec_quantity == 0.0
      assert event.create_date == ~U[2025-12-09 12:05:35.277Z]
      assert event.transaction_date == ~U[2025-12-09 12:05:35.277Z]
    end

    test "parses the optional parent_id and tag when present" do
      event =
        Fixtures.order_event()
        |> Map.merge(%{"parent_id" => 42, "tag" => "my-strategy"})
        |> Streaming.parse_order_event()

      assert event.parent_id == 42
      assert event.tag == "my-strategy"
    end

    test "parses a heartbeat event, truncating nanosecond precision" do
      json = Jason.encode!(Fixtures.heartbeat_event())

      assert {:ok, %HeartbeatEvent{status: "active", timestamp: timestamp}} =
               Streaming.parse_account_event(json)

      assert timestamp == ~U[2025-12-10 18:02:51.028929Z]
    end

    test "returns an error for an unrecognized event type" do
      assert {:error, {:unknown_event_type, "margin_call"}} =
               Streaming.parse_account_event(~s({"event":"margin_call"}))
    end

    test "returns an error when the event key is missing" do
      assert {:error, :missing_event} = Streaming.parse_account_event(~s({"status":"open"}))
    end

    test "returns an error for invalid JSON" do
      assert {:error, :invalid_json} = Streaming.parse_account_event("not json")
    end

    test "leaves timestamps nil when they are unparseable" do
      event = Streaming.parse_order_event(%{"transaction_date" => "yesterday"})

      assert event.transaction_date == nil
    end
  end

  describe "parse_account_event_from_map/1" do
    test "accepts an already decoded map" do
      assert {:ok, %OrderEvent{status: "open"}} =
               Streaming.parse_account_event_from_map(Fixtures.order_event())
    end

    test "does not confuse a market event for an account event" do
      assert {:error, :missing_event} =
               Streaming.parse_account_event_from_map(Fixtures.quote_event())
    end
  end
end
