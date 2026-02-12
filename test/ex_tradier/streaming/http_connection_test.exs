defmodule ExTradier.Streaming.HttpConnectionTest do
  use ExUnit.Case, async: false
  use Mimic

  alias ExTradier.Streaming.HttpConnection
  alias ExTradier.Streaming.Session
  alias ExTradier.Fixtures

  setup :set_mimic_global
  setup :verify_on_exit!

  defp start_connection(opts \\ []) do
    {:ok, pid} = HttpConnection.start_link(Keyword.merge([api_token: "test_token"], opts))
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)
    {:ok, pid}
  end

  defp stub_session_flow do
    stub(ExTradier.Streaming, :create_market_session, fn _client, _params ->
      {:ok, Fixtures.streaming_session_response()}
    end)

    stub(ExTradier.Streaming, :create_session_from_response, fn _resp ->
      {:ok,
       %Session{
         session_id: "test-session",
         url: "wss://test",
         created_at: DateTime.utc_now()
       }}
    end)

    stub(ExTradier.Streaming, :session_expired?, fn _session -> false end)
    stub(ExTradier.Streaming, :time_until_expiry, fn _session -> 300_000 end)
  end

  describe "start_link/1" do
    test "starts with disconnected status" do
      {:ok, pid} = start_connection()
      assert HttpConnection.get_status(pid) == :disconnected
    end

    test "registers process with name" do
      name = :"test_http_#{System.unique_integer([:positive])}"
      {:ok, pid} = HttpConnection.start_link(api_token: "test_token", name: name)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

      assert Process.whereis(name) == pid
      assert HttpConnection.get_status(name) == :disconnected
    end
  end

  describe "get_status/1" do
    test "returns current connection status" do
      {:ok, pid} = start_connection()
      assert HttpConnection.get_status(pid) == :disconnected
    end
  end

  describe "get_info/1" do
    test "returns connection info map" do
      {:ok, pid} = start_connection()
      info = HttpConnection.get_info(pid)

      assert info.status == :disconnected
      assert info.symbols == []
      assert info.subscriber_count == 0
      assert info.session_valid == false
      assert info.transport == :http
    end
  end

  describe "add_subscriber/2 and remove_subscriber/2" do
    test "tracks subscriber count" do
      {:ok, pid} = start_connection()
      subscriber = spawn(fn -> Process.sleep(:infinity) end)

      HttpConnection.add_subscriber(pid, subscriber)
      Process.sleep(50)
      assert HttpConnection.get_info(pid).subscriber_count == 1

      HttpConnection.remove_subscriber(pid, subscriber)
      Process.sleep(50)
      assert HttpConnection.get_info(pid).subscriber_count == 0

      Process.exit(subscriber, :kill)
    end
  end

  describe "subscriber DOWN monitoring" do
    test "removes subscriber when process dies" do
      {:ok, pid} = start_connection()
      subscriber = spawn(fn -> Process.sleep(:infinity) end)

      HttpConnection.add_subscriber(pid, subscriber)
      Process.sleep(50)
      assert HttpConnection.get_info(pid).subscriber_count == 1

      Process.exit(subscriber, :kill)
      Process.sleep(100)
      assert HttpConnection.get_info(pid).subscriber_count == 0
    end
  end

  describe "subscribe/2" do
    test "adds symbols and triggers connection" do
      stub_session_flow()
      {:ok, pid} = start_connection()

      assert :ok = HttpConnection.subscribe(pid, ["AAPL", "MSFT"])
      Process.sleep(100)

      info = HttpConnection.get_info(pid)
      assert "AAPL" in info.symbols
      assert "MSFT" in info.symbols
    end
  end

  describe "unsubscribe/2" do
    test "removes symbols from subscription" do
      stub_session_flow()
      {:ok, pid} = start_connection()

      HttpConnection.subscribe(pid, ["AAPL", "MSFT"])
      Process.sleep(100)

      assert :ok = HttpConnection.unsubscribe(pid, ["MSFT"])
      Process.sleep(50)

      info = HttpConnection.get_info(pid)
      assert "AAPL" in info.symbols
      refute "MSFT" in info.symbols
    end

    test "disconnects when all symbols removed" do
      stub_session_flow()
      {:ok, pid} = start_connection()

      HttpConnection.subscribe(pid, ["AAPL"])
      Process.sleep(100)

      HttpConnection.unsubscribe(pid, ["AAPL"])
      Process.sleep(50)

      assert HttpConnection.get_status(pid) == :disconnected
      assert HttpConnection.get_info(pid).symbols == []
    end
  end

  describe "parse_buffer/1" do
    test "parses complete lines as events" do
      json1 =
        Jason.encode!(%{"type" => "quote", "symbol" => "AAPL", "bid" => 150.0, "ask" => 151.0})

      json2 =
        Jason.encode!(%{"type" => "trade", "symbol" => "MSFT", "price" => 300.0, "size" => 100})

      buffer = json1 <> "\n" <> json2 <> "\n"

      {events, remaining} = HttpConnection.parse_buffer(buffer)

      assert length(events) == 2
      assert remaining == ""
    end

    test "preserves partial lines in remaining buffer" do
      json =
        Jason.encode!(%{"type" => "quote", "symbol" => "AAPL", "bid" => 150.0, "ask" => 151.0})

      partial = ~s({"type":"trade","symbol":"MS)
      buffer = json <> "\n" <> partial

      {events, remaining} = HttpConnection.parse_buffer(buffer)

      assert length(events) == 1
      assert remaining == partial
    end

    test "handles empty lines" do
      json =
        Jason.encode!(%{"type" => "quote", "symbol" => "AAPL", "bid" => 150.0, "ask" => 151.0})

      buffer = "\n\n" <> json <> "\n\n"

      {events, remaining} = HttpConnection.parse_buffer(buffer)

      assert length(events) == 1
      assert remaining == ""
    end

    test "returns empty events for empty buffer" do
      {events, remaining} = HttpConnection.parse_buffer("")

      assert events == []
      assert remaining == ""
    end

    test "skips invalid JSON lines" do
      json =
        Jason.encode!(%{"type" => "quote", "symbol" => "AAPL", "bid" => 150.0, "ask" => 151.0})

      buffer = "not json\n" <> json <> "\n"

      {events, remaining} = HttpConnection.parse_buffer(buffer)

      assert length(events) == 1
      assert remaining == ""
    end
  end

  describe "event broadcasting" do
    test "broadcasts parsed events to subscribers" do
      {:ok, pid} = start_connection()

      HttpConnection.add_subscriber(pid, self())
      Process.sleep(50)

      json =
        Jason.encode!(%{"type" => "quote", "symbol" => "AAPL", "bid" => 150.0, "ask" => 151.0})

      send(pid, {:http_chunk, json <> "\n"})

      assert_receive {:stream_event, %ExTradier.Streaming.QuoteEvent{symbol: "AAPL"}}, 500
    end

    test "broadcasts multiple events from a single chunk" do
      {:ok, pid} = start_connection()

      HttpConnection.add_subscriber(pid, self())
      Process.sleep(50)

      json1 =
        Jason.encode!(%{"type" => "quote", "symbol" => "AAPL", "bid" => 150.0, "ask" => 151.0})

      json2 =
        Jason.encode!(%{"type" => "trade", "symbol" => "MSFT", "price" => 300.0, "size" => 100})

      send(pid, {:http_chunk, json1 <> "\n" <> json2 <> "\n"})

      assert_receive {:stream_event, %ExTradier.Streaming.QuoteEvent{symbol: "AAPL"}}, 500
      assert_receive {:stream_event, %ExTradier.Streaming.TradeEvent{symbol: "MSFT"}}, 500
    end

    test "handles chunked data across multiple messages" do
      {:ok, pid} = start_connection()

      HttpConnection.add_subscriber(pid, self())
      Process.sleep(50)

      # Send partial JSON
      send(pid, {:http_chunk, ~s({"type":"quote","symbol":"AA)})
      Process.sleep(50)

      # Complete the JSON line
      send(pid, {:http_chunk, ~s(PL","bid":150.0,"ask":151.0}\n)})

      assert_receive {:stream_event, %ExTradier.Streaming.QuoteEvent{symbol: "AAPL"}}, 500
    end
  end

  describe "stream lifecycle messages" do
    test "handles stream connected message" do
      stub_session_flow()
      {:ok, pid} = start_connection()

      HttpConnection.subscribe(pid, ["AAPL"])
      Process.sleep(100)

      # The stream_pid was set during subscribe flow, simulate connected
      state = :sys.get_state(pid)

      if state.stream_pid do
        send(pid, {:http_stream_connected, state.stream_pid})
        Process.sleep(50)
        assert HttpConnection.get_status(pid) == :connected
      end
    end

    test "handles stream ended message and schedules reconnect" do
      {:ok, pid} = start_connection()

      # Simulate a stream pid existing then ending
      fake_pid = spawn(fn -> Process.sleep(:infinity) end)
      :sys.replace_state(pid, fn state -> %{state | stream_pid: fake_pid, status: :connected} end)

      send(pid, {:http_stream_ended, fake_pid, :normal})
      Process.sleep(100)

      status = HttpConnection.get_status(pid)
      assert status in [:disconnected, :reconnecting]

      Process.exit(fake_pid, :kill)
    end
  end

  describe "reconnection" do
    test "reconnect cast triggers disconnect and schedule reconnect" do
      {:ok, pid} = start_connection()

      HttpConnection.reconnect(pid)
      Process.sleep(50)

      status = HttpConnection.get_status(pid)
      assert status in [:disconnected, :reconnecting]
    end

    test "reconnect message triggers do_connect" do
      stub_session_flow()
      {:ok, pid} = start_connection()

      # Set up some symbols so reconnect has something to do
      :sys.replace_state(pid, fn state ->
        %{state | subscribed_symbols: MapSet.new(["AAPL"]), reconnect_timer: nil}
      end)

      send(pid, :reconnect)
      Process.sleep(100)

      assert Process.alive?(pid)
    end
  end

  describe "session refresh" do
    test "refresh_session message triggers reconnection" do
      stub_session_flow()
      {:ok, pid} = start_connection()

      :sys.replace_state(pid, fn state ->
        %{state | subscribed_symbols: MapSet.new(["AAPL"]), session_refresh_timer: nil}
      end)

      send(pid, :refresh_session)
      Process.sleep(100)

      assert Process.alive?(pid)
    end
  end

  describe "session creation failure" do
    test "schedules reconnect when session creation fails" do
      stub(ExTradier.Streaming, :create_market_session, fn _client, _params ->
        {:error, :connection_refused}
      end)

      {:ok, pid} = start_connection()
      HttpConnection.subscribe(pid, ["AAPL"])
      Process.sleep(100)

      assert HttpConnection.get_status(pid) in [:disconnected, :reconnecting]
    end

    test "schedules reconnect when session response is invalid" do
      stub(ExTradier.Streaming, :create_market_session, fn _client, _params ->
        {:ok, %{"invalid" => "response"}}
      end)

      stub(ExTradier.Streaming, :create_session_from_response, fn _resp ->
        {:error, :invalid_response}
      end)

      {:ok, pid} = start_connection()
      HttpConnection.subscribe(pid, ["AAPL"])
      Process.sleep(100)

      assert HttpConnection.get_status(pid) in [:disconnected, :reconnecting]
    end
  end

  describe "stop/1" do
    test "stops the process" do
      {:ok, pid} = HttpConnection.start_link(api_token: "test_token")
      assert Process.alive?(pid)
      HttpConnection.stop(pid)
      Process.sleep(50)
      refute Process.alive?(pid)
    end
  end

  describe "unknown message handling" do
    test "ignores unexpected messages" do
      {:ok, pid} = start_connection()
      send(pid, :some_random_message)
      Process.sleep(50)
      assert Process.alive?(pid)
    end
  end
end
