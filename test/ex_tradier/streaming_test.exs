defmodule ExTradier.StreamingTest do
  use ExUnit.Case, async: true

  alias ExTradier.Streaming
  alias ExTradier.Streaming.{QuoteEvent, TradeEvent, SummaryEvent, TimesaleEvent, Session}
  alias ExTradier.Fixtures

  describe "create_session_from_response/1" do
    test "creates session from valid response" do
      response = Fixtures.streaming_session_response()
      assert {:ok, %Session{} = session} = Streaming.create_session_from_response(response)
      assert session.session_id == "session-abc123def456"
      assert session.url == "wss://stream.tradier.com/v1/markets/events"
      assert %DateTime{} = session.created_at
    end

    test "returns error for invalid response" do
      assert {:error, :invalid_response} = Streaming.create_session_from_response(%{})
    end
  end

  describe "parse_event/1" do
    test "parses valid JSON" do
      json = Jason.encode!(Fixtures.quote_event())
      assert {:ok, data} = Streaming.parse_event(json)
      assert data["type"] == "quote"
      assert data["symbol"] == "AAPL"
    end

    test "returns error for invalid JSON" do
      assert {:error, :invalid_json} = Streaming.parse_event("not json")
    end
  end

  describe "parse_typed_event/1" do
    test "parses quote event" do
      json = Jason.encode!(Fixtures.quote_event())
      assert {:ok, %QuoteEvent{} = event} = Streaming.parse_typed_event(json)
      assert event.symbol == "AAPL"
      assert event.bid == 150.20
      assert event.ask == 150.30
      assert event.bid_size == 2
      assert event.ask_size == 3
    end

    test "parses trade event" do
      json = Jason.encode!(Fixtures.trade_event())
      assert {:ok, %TradeEvent{} = event} = Streaming.parse_typed_event(json)
      assert event.symbol == "AAPL"
      assert event.price == 150.25
      assert event.size == 100
    end

    test "parses summary event" do
      json = Jason.encode!(Fixtures.summary_event())
      assert {:ok, %SummaryEvent{} = event} = Streaming.parse_typed_event(json)
      assert event.symbol == "AAPL"
      assert event.open == 149.50
      assert event.high == 151.00
    end

    test "parses timesale event" do
      json = Jason.encode!(Fixtures.timesale_event())
      assert {:ok, %TimesaleEvent{} = event} = Streaming.parse_typed_event(json)
      assert event.symbol == "AAPL"
      assert event.last == 150.25
      assert event.size == 100
    end

    test "returns error for unknown event type" do
      json = Jason.encode!(%{"type" => "unknown"})
      assert {:error, {:unknown_event_type, "unknown"}} = Streaming.parse_typed_event(json)
    end
  end

  describe "build_websocket_url/3" do
    test "builds market URL" do
      url = Streaming.build_websocket_url("abc123", :market)
      assert url == "wss://ws.tradier.com/v1/markets/events?sessionid=abc123"
    end

    test "builds account URL" do
      url = Streaming.build_websocket_url("abc123", :account)
      assert url == "wss://ws.tradier.com/v1/accounts/events?sessionid=abc123"
    end

    test "builds sandbox URL" do
      url = Streaming.build_websocket_url("abc123", :market, true)
      assert url == "wss://sandbox-ws.tradier.com/v1/markets/events?sessionid=abc123"
    end
  end

  describe "build_subscription_payload/3" do
    test "builds payload" do
      payload = Streaming.build_subscription_payload(["AAPL", "MSFT"], ["quote", "trade"])
      assert payload.symbols == ["AAPL", "MSFT"]
      assert payload.filter == ["quote", "trade"]
      assert payload.linebreak == true
    end
  end

  describe "session_expired?/1" do
    test "returns false for fresh session" do
      session = %Session{
        session_id: "abc",
        url: "wss://example.com",
        created_at: DateTime.utc_now()
      }

      refute Streaming.session_expired?(session)
    end

    test "returns true for old session" do
      session = %Session{
        session_id: "abc",
        url: "wss://example.com",
        created_at: DateTime.add(DateTime.utc_now(), -6, :minute)
      }

      assert Streaming.session_expired?(session)
    end

    test "returns true for nil session" do
      assert Streaming.session_expired?(nil)
    end
  end

  describe "time_until_expiry/1" do
    test "returns positive value for fresh session" do
      session = %Session{
        session_id: "abc",
        url: "wss://example.com",
        created_at: DateTime.utc_now()
      }

      ttl = Streaming.time_until_expiry(session)
      assert ttl > 0
      assert ttl <= 300_000
    end

    test "returns 0 for expired session" do
      session = %Session{
        session_id: "abc",
        url: "wss://example.com",
        created_at: DateTime.add(DateTime.utc_now(), -10, :minute)
      }

      assert Streaming.time_until_expiry(session) == 0
    end
  end
end
