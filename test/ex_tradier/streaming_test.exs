defmodule ExTradier.StreamingTest do
  use ExUnit.Case, async: true

  alias ExTradier.Fixtures
  alias ExTradier.Streaming
  alias ExTradier.Streaming.{QuoteEvent, Session, SummaryEvent, TimesaleEvent, TradeEvent}

  describe "create_market_session/2" do
    test "creates a market streaming session" do
      Req.Test.expect(ExTradier.StreamingTest.MarketSession, fn conn ->
        assert conn.request_path == "/v1/markets/events/session"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.streaming_session_response())
      end)

      client = Fixtures.test_client(ExTradier.StreamingTest.MarketSession)

      assert {:ok, %{"stream" => stream}} =
               Streaming.create_market_session(client, %{
                 symbols: ["AAPL"],
                 filter: ["quote"]
               })

      assert stream["sessionid"] == "session-abc123def456"
    end
  end

  describe "create_account_session/2" do
    test "creates an account streaming session" do
      Req.Test.expect(ExTradier.StreamingTest.AccountSession, fn conn ->
        assert conn.request_path == "/v1/accounts/events/session"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.account_session_response())
      end)

      client = Fixtures.test_client(ExTradier.StreamingTest.AccountSession)

      assert {:ok, %{"stream" => stream}} =
               Streaming.create_account_session(client, "VA000001")

      assert stream["sessionid"] == "account-session-xyz789"
    end
  end

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

  describe "parse_typed_event_from_map/1" do
    test "parses quote map to QuoteEvent" do
      assert {:ok, %QuoteEvent{symbol: "AAPL"}} =
               Streaming.parse_typed_event_from_map(Fixtures.quote_event())
    end

    test "parses trade map to TradeEvent" do
      assert {:ok, %TradeEvent{symbol: "AAPL"}} =
               Streaming.parse_typed_event_from_map(Fixtures.trade_event())
    end

    test "parses summary map to SummaryEvent" do
      assert {:ok, %SummaryEvent{symbol: "AAPL"}} =
               Streaming.parse_typed_event_from_map(Fixtures.summary_event())
    end

    test "parses timesale map to TimesaleEvent" do
      assert {:ok, %TimesaleEvent{symbol: "AAPL"}} =
               Streaming.parse_typed_event_from_map(Fixtures.timesale_event())
    end

    test "returns error for unknown type" do
      assert {:error, {:unknown_event_type, "foo"}} =
               Streaming.parse_typed_event_from_map(%{"type" => "foo"})
    end

    test "returns error for missing type" do
      assert {:error, :missing_type} = Streaming.parse_typed_event_from_map(%{"symbol" => "AAPL"})
    end
  end

  describe "parse_quote_event/1" do
    test "parses all fields" do
      event = Streaming.parse_quote_event(Fixtures.quote_event())
      assert %QuoteEvent{} = event
      assert event.symbol == "AAPL"
      assert event.bid == 150.20
      assert event.bid_size == 2
      assert event.bid_exchange == "Q"
      assert event.ask == 150.30
      assert event.ask_size == 3
      assert event.ask_exchange == "P"
    end
  end

  describe "parse_trade_event/1" do
    test "parses all fields" do
      event = Streaming.parse_trade_event(Fixtures.trade_event())
      assert %TradeEvent{} = event
      assert event.symbol == "AAPL"
      assert event.price == 150.25
      assert event.size == 100
      assert event.exchange == "Q"
      assert event.cvol == 45_123_456
      assert event.last == 150.25
    end
  end

  describe "parse_summary_event/1" do
    test "parses all fields" do
      event = Streaming.parse_summary_event(Fixtures.summary_event())
      assert %SummaryEvent{} = event
      assert event.symbol == "AAPL"
      assert event.open == 149.50
      assert event.high == 151.00
      assert event.low == 149.25
      assert event.prev_close == 149.00
    end
  end

  describe "parse_timesale_event/1" do
    test "parses all fields" do
      event = Streaming.parse_timesale_event(Fixtures.timesale_event())
      assert %TimesaleEvent{} = event
      assert event.symbol == "AAPL"
      assert event.exchange == "Q"
      assert event.bid == 150.20
      assert event.ask == 150.30
      assert event.last == 150.25
      assert event.size == 100
    end
  end

  describe "parse_tradex_event/1" do
    test "parses all fields" do
      event = Streaming.parse_tradex_event(Fixtures.tradex_event())
      assert %Streaming.TradexEvent{} = event
      assert event.symbol == "AAPL"
      assert event.price == 150.25
      assert event.size == 100
      assert event.exchange == "Q"
      assert event.cvol == 45_123_456
      assert event.last == 150.25
      assert event.open == 149.50
      assert event.high == 151.00
      assert event.low == 149.25
      assert event.close == 150.25
      assert event.prev_close == 149.00
      assert event.volume == 45_123_456
      assert event.vwap == 150.10
    end
  end

  describe "parse_typed_event tradex" do
    test "parses tradex from JSON string" do
      json = Jason.encode!(Fixtures.tradex_event())
      assert {:ok, %Streaming.TradexEvent{symbol: "AAPL"}} = Streaming.parse_typed_event(json)
    end

    test "parses tradex from map" do
      assert {:ok, %Streaming.TradexEvent{symbol: "AAPL"}} =
               Streaming.parse_typed_event_from_map(Fixtures.tradex_event())
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

    test "includes session ID when provided" do
      payload =
        Streaming.build_subscription_payload(["AAPL"], ["quote"], "session-123")

      assert payload.sessionid == "session-123"
    end
  end

  describe "build_subscription_payload/4 with opts" do
    test "includes validOnly when valid_only option is set" do
      payload =
        Streaming.build_subscription_payload(["AAPL"], ["quote"], nil, valid_only: true)

      assert payload.validOnly == true
    end

    test "includes advancedDetails when advanced_details option is set" do
      payload =
        Streaming.build_subscription_payload(["AAPL"], ["quote"], nil, advanced_details: true)

      assert payload.advancedDetails == true
    end

    test "omits optional fields when not provided" do
      payload = Streaming.build_subscription_payload(["AAPL"], ["quote"], nil, [])
      refute Map.has_key?(payload, :validOnly)
      refute Map.has_key?(payload, :advancedDetails)
    end
  end

  describe "encode_subscription_payload/3" do
    test "returns JSON-encoded payload" do
      assert {:ok, json} = Streaming.encode_subscription_payload(["AAPL"], ["quote"])
      decoded = Jason.decode!(json)
      assert decoded["symbols"] == ["AAPL"]
      assert decoded["filter"] == ["quote"]
      assert decoded["linebreak"] == true
    end

    test "includes session ID in encoded payload" do
      assert {:ok, json} =
               Streaming.encode_subscription_payload(["AAPL"], ["quote"], "sess-abc")

      decoded = Jason.decode!(json)
      assert decoded["sessionid"] == "sess-abc"
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

    test "returns 0 for non-session" do
      assert Streaming.time_until_expiry(nil) == 0
    end
  end

  describe "session_expiry_ms/0" do
    test "returns 5 minutes in milliseconds" do
      assert Streaming.session_expiry_ms() == 300_000
    end
  end

  describe "validate_session/1" do
    test "returns ok for valid session" do
      session = %Session{
        session_id: "abc",
        url: "wss://example.com",
        created_at: DateTime.utc_now()
      }

      assert {:ok, :valid} = Streaming.validate_session(session)
    end

    test "returns error for expired session" do
      session = %Session{
        session_id: "abc",
        url: "wss://example.com",
        created_at: DateTime.add(DateTime.utc_now(), -10, :minute)
      }

      assert {:error, :expired} = Streaming.validate_session(session)
    end

    test "returns error for invalid input" do
      assert {:error, :invalid_session} = Streaming.validate_session("not a session")
    end
  end

  describe "create_market_session/2 with param coercion" do
    test "handles non-list symbols" do
      Req.Test.expect(ExTradier.StreamingTest.MarketSessionStr, fn conn ->
        assert conn.request_path == "/v1/markets/events/session"
        Req.Test.json(conn, Fixtures.streaming_session_response())
      end)

      client = Fixtures.test_client(ExTradier.StreamingTest.MarketSessionStr)

      assert {:ok, _} =
               Streaming.create_market_session(client, %{symbols: "AAPL", filter: "quote"})
    end

    test "handles no params" do
      Req.Test.expect(ExTradier.StreamingTest.MarketSessionEmpty, fn conn ->
        Req.Test.json(conn, Fixtures.streaming_session_response())
      end)

      client = Fixtures.test_client(ExTradier.StreamingTest.MarketSessionEmpty)
      assert {:ok, _} = Streaming.create_market_session(client)
    end
  end
end
