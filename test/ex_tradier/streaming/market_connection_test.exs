defmodule ExTradier.Streaming.MarketConnectionTest do
  use ExUnit.Case, async: false
  use Mimic

  alias ExTradier.Streaming.MarketConnection
  alias ExTradier.Streaming.Session
  alias ExTradier.Fixtures

  setup :set_mimic_global
  setup :verify_on_exit!

  defp start_connection(opts \\ []) do
    {:ok, pid} = MarketConnection.start_link(Keyword.merge([api_token: "test_token"], opts))
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)
    {:ok, pid}
  end

  defp stub_connection_flow do
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

    stub(ExTradier.Streaming, :build_websocket_url, fn _session_id, _type, _sandbox ->
      "wss://test/markets/events?sessionid=test-session"
    end)

    stub(ExTradier.Streaming, :build_subscription_payload, fn symbols, filters, _session_id ->
      %{symbols: symbols, filter: filters, linebreak: true}
    end)

    stub(ExTradier.Streaming.Client, :start_link, fn _url, parent ->
      pid = spawn(fn -> Process.sleep(:infinity) end)
      send(parent, {:stream_connected, pid})
      {:ok, pid}
    end)

    stub(ExTradier.Streaming.Client, :send_subscription, fn _pid, _payload -> :ok end)
    stub(ExTradier.Streaming.Client, :close, fn _pid -> :ok end)
  end

  describe "start_link/1" do
    test "starts with disconnected status" do
      {:ok, pid} = start_connection()
      assert MarketConnection.get_status(pid) == :disconnected
    end
  end

  describe "get_status/1" do
    test "returns current connection status" do
      {:ok, pid} = start_connection()
      assert MarketConnection.get_status(pid) == :disconnected
    end
  end

  describe "get_info/1" do
    test "returns connection info map" do
      {:ok, pid} = start_connection()
      info = MarketConnection.get_info(pid)

      assert info.status == :disconnected
      assert info.symbols == []
      assert info.subscriber_count == 0
      assert info.session_valid == false
    end
  end

  describe "add_subscriber/2 and remove_subscriber/2" do
    test "tracks subscriber count" do
      {:ok, pid} = start_connection()
      subscriber = spawn(fn -> Process.sleep(:infinity) end)

      MarketConnection.add_subscriber(pid, subscriber)
      Process.sleep(50)
      assert MarketConnection.get_info(pid).subscriber_count == 1

      MarketConnection.remove_subscriber(pid, subscriber)
      Process.sleep(50)
      assert MarketConnection.get_info(pid).subscriber_count == 0

      Process.exit(subscriber, :kill)
    end
  end

  describe "subscribe/2" do
    test "adds symbols and triggers connection" do
      stub_connection_flow()
      {:ok, pid} = start_connection()

      assert :ok = MarketConnection.subscribe(pid, ["AAPL", "MSFT"])
      Process.sleep(100)

      info = MarketConnection.get_info(pid)
      assert "AAPL" in info.symbols
      assert "MSFT" in info.symbols
      assert info.status == :connected
    end
  end

  describe "unsubscribe/2" do
    test "removes symbols from subscription" do
      stub_connection_flow()
      {:ok, pid} = start_connection()

      MarketConnection.subscribe(pid, ["AAPL", "MSFT"])
      Process.sleep(100)

      assert :ok = MarketConnection.unsubscribe(pid, ["MSFT"])
      Process.sleep(50)

      info = MarketConnection.get_info(pid)
      assert "AAPL" in info.symbols
      refute "MSFT" in info.symbols
    end
  end

  describe "reconnect/1" do
    test "triggers reconnection" do
      stub_connection_flow()
      {:ok, pid} = start_connection()

      MarketConnection.subscribe(pid, ["AAPL"])
      Process.sleep(100)
      assert MarketConnection.get_status(pid) == :connected

      MarketConnection.reconnect(pid)
      Process.sleep(50)
      assert MarketConnection.get_status(pid) in [:reconnecting, :connecting, :connected]
    end
  end

  describe "stop/1" do
    test "stops the process" do
      {:ok, pid} = MarketConnection.start_link(api_token: "test_token")
      assert Process.alive?(pid)
      MarketConnection.stop(pid)
      Process.sleep(50)
      refute Process.alive?(pid)
    end
  end

  describe "subscriber DOWN monitoring" do
    test "removes subscriber when process dies" do
      {:ok, pid} = start_connection()
      subscriber = spawn(fn -> Process.sleep(:infinity) end)

      MarketConnection.add_subscriber(pid, subscriber)
      Process.sleep(50)
      assert MarketConnection.get_info(pid).subscriber_count == 1

      Process.exit(subscriber, :kill)
      Process.sleep(100)
      assert MarketConnection.get_info(pid).subscriber_count == 0
    end
  end

  describe "stream message broadcasting" do
    test "broadcasts parsed events to subscribers" do
      stub_connection_flow()

      stub(ExTradier.Streaming, :parse_typed_event, fn _msg ->
        {:ok,
         %ExTradier.Streaming.QuoteEvent{
           symbol: "AAPL",
           bid: 150.0,
           ask: 151.0
         }}
      end)

      {:ok, pid} = start_connection()
      MarketConnection.add_subscriber(pid, self())
      MarketConnection.subscribe(pid, ["AAPL"])
      Process.sleep(100)

      ws_pid = get_ws_pid(pid)
      send(pid, {:stream_message, ws_pid, ~s({"type":"quote","symbol":"AAPL"})})

      assert_receive {:stream_event, %ExTradier.Streaming.QuoteEvent{symbol: "AAPL"}}, 500
    end

    test "handles parse errors gracefully" do
      stub_connection_flow()

      stub(ExTradier.Streaming, :parse_typed_event, fn _msg ->
        {:error, :invalid_json}
      end)

      {:ok, pid} = start_connection()
      MarketConnection.subscribe(pid, ["AAPL"])
      Process.sleep(100)

      ws_pid = get_ws_pid(pid)
      send(pid, {:stream_message, ws_pid, "bad data"})
      Process.sleep(50)

      # Process should still be alive after parse error
      assert Process.alive?(pid)
    end
  end

  describe "stream disconnection" do
    test "triggers reconnect on disconnect" do
      stub_connection_flow()
      {:ok, pid} = start_connection()

      MarketConnection.subscribe(pid, ["AAPL"])
      Process.sleep(100)
      assert MarketConnection.get_status(pid) == :connected

      ws_pid = get_ws_pid(pid)
      send(pid, {:stream_disconnected, ws_pid, :normal})
      Process.sleep(50)

      assert MarketConnection.get_status(pid) in [:disconnected, :reconnecting]
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

  describe "session creation failure" do
    test "schedules reconnect when session creation fails" do
      stub(ExTradier.Streaming, :create_market_session, fn _client, _params ->
        {:error, :connection_refused}
      end)

      {:ok, pid} = start_connection()
      MarketConnection.subscribe(pid, ["AAPL"])
      Process.sleep(100)

      assert MarketConnection.get_status(pid) in [:disconnected, :reconnecting]
    end

    test "schedules reconnect when session response is invalid" do
      stub(ExTradier.Streaming, :create_market_session, fn _client, _params ->
        {:ok, %{"invalid" => "response"}}
      end)

      stub(ExTradier.Streaming, :create_session_from_response, fn _resp ->
        {:error, :invalid_response}
      end)

      {:ok, pid} = start_connection()
      MarketConnection.subscribe(pid, ["AAPL"])
      Process.sleep(100)

      assert MarketConnection.get_status(pid) in [:disconnected, :reconnecting]
    end
  end

  describe "websocket connection failure" do
    test "schedules reconnect when websocket fails to start" do
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

      stub(ExTradier.Streaming, :build_websocket_url, fn _session_id, _type, _sandbox ->
        "wss://test/markets/events?sessionid=test-session"
      end)

      stub(ExTradier.Streaming.Client, :start_link, fn _url, _parent ->
        {:error, :connection_refused}
      end)

      {:ok, pid} = start_connection()
      MarketConnection.subscribe(pid, ["AAPL"])
      Process.sleep(100)

      assert MarketConnection.get_status(pid) in [:disconnected, :reconnecting]
    end
  end

  describe "unsubscribe while connected" do
    test "sends subscription update when connected" do
      stub_connection_flow()
      {:ok, pid} = start_connection()

      MarketConnection.subscribe(pid, ["AAPL", "MSFT", "GOOG"])
      Process.sleep(100)
      assert MarketConnection.get_status(pid) == :connected

      MarketConnection.unsubscribe(pid, ["MSFT"])
      Process.sleep(50)

      info = MarketConnection.get_info(pid)
      assert "AAPL" in info.symbols
      assert "GOOG" in info.symbols
      refute "MSFT" in info.symbols
    end
  end

  describe "reconnect timer" do
    test "reconnect message triggers do_connect" do
      stub_connection_flow()
      {:ok, pid} = start_connection()

      MarketConnection.subscribe(pid, ["AAPL"])
      Process.sleep(100)
      assert MarketConnection.get_status(pid) == :connected

      # Disconnect, then send :reconnect directly (simulating timer fire)
      ws_pid = get_ws_pid(pid)
      send(pid, {:stream_disconnected, ws_pid, :normal})
      Process.sleep(50)

      # Directly send :reconnect to trigger the reconnect path
      send(pid, :reconnect)
      Process.sleep(100)

      assert MarketConnection.get_status(pid) in [:connecting, :connected]
    end
  end

  describe "session refresh" do
    test "refresh_session message triggers session refresh" do
      stub_connection_flow()
      {:ok, pid} = start_connection()

      MarketConnection.subscribe(pid, ["AAPL"])
      Process.sleep(100)
      assert MarketConnection.get_status(pid) == :connected

      # Directly send :refresh_session to trigger the refresh path
      send(pid, :refresh_session)
      Process.sleep(100)

      # Process should still be alive and connected after refresh
      assert Process.alive?(pid)
      assert MarketConnection.get_status(pid) == :connected
    end
  end

  describe "maybe_connect guards" do
    test "subscribe when already connected is a no-op for connection" do
      stub_connection_flow()
      {:ok, pid} = start_connection()

      MarketConnection.subscribe(pid, ["AAPL"])
      Process.sleep(100)
      assert MarketConnection.get_status(pid) == :connected

      # Subscribe again while already connected
      assert :ok = MarketConnection.subscribe(pid, ["MSFT"])
      Process.sleep(50)

      info = MarketConnection.get_info(pid)
      assert "AAPL" in info.symbols
      assert "MSFT" in info.symbols
      assert info.status == :connected
    end
  end

  describe "terminate with active websocket" do
    test "closes websocket on terminate" do
      stub_connection_flow()
      {:ok, pid} = start_connection()

      MarketConnection.subscribe(pid, ["AAPL"])
      Process.sleep(100)
      assert MarketConnection.get_status(pid) == :connected

      # Stop should call terminate which closes the websocket
      MarketConnection.stop(pid)
      Process.sleep(50)
      refute Process.alive?(pid)
    end
  end

  describe "start_link/1 with name" do
    test "registers process with name" do
      stub_connection_flow()
      name = :"test_market_#{System.unique_integer([:positive])}"
      {:ok, pid} = MarketConnection.start_link(api_token: "test_token", name: name)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

      assert Process.whereis(name) == pid
      assert MarketConnection.get_status(name) == :disconnected
    end
  end

  defp get_ws_pid(connection_pid) do
    state = :sys.get_state(connection_pid)
    state.websocket_pid
  end
end
