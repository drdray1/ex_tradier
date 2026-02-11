defmodule ExTradier.FacadeStreamingTest do
  use ExUnit.Case, async: false
  use Mimic

  alias ExTradier.Streaming.{MarketConnection, Session}

  setup :set_mimic_global
  setup :verify_on_exit!

  defp stub_connection_flow do
    stub(ExTradier.Streaming, :create_market_session, fn _client, _params ->
      {:ok, ExTradier.Fixtures.streaming_session_response()}
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

  describe "stream_add_subscriber/2 and stream_remove_subscriber/2" do
    test "adds and removes subscribers via facade" do
      {:ok, pid} = MarketConnection.start_link(api_token: "test_token")
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

      subscriber = spawn(fn -> Process.sleep(:infinity) end)
      ExTradier.stream_add_subscriber(pid, subscriber)
      Process.sleep(50)
      assert ExTradier.stream_info(pid).subscriber_count == 1

      ExTradier.stream_remove_subscriber(pid, subscriber)
      Process.sleep(50)
      assert ExTradier.stream_info(pid).subscriber_count == 0

      Process.exit(subscriber, :kill)
    end
  end

  describe "stream_status/1" do
    test "returns status via facade" do
      {:ok, pid} = MarketConnection.start_link(api_token: "test_token")
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

      assert ExTradier.stream_status(pid) == :disconnected
    end
  end

  describe "stream_info/1" do
    test "returns info via facade" do
      {:ok, pid} = MarketConnection.start_link(api_token: "test_token")
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

      info = ExTradier.stream_info(pid)
      assert info.status == :disconnected
      assert info.symbols == []
    end
  end

  describe "stream_reconnect/1" do
    test "triggers reconnect via facade" do
      stub_connection_flow()
      {:ok, pid} = MarketConnection.start_link(api_token: "test_token")
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

      ExTradier.stream_subscribe(pid, ["AAPL"])
      Process.sleep(100)

      ExTradier.stream_reconnect(pid)
      Process.sleep(50)
      assert ExTradier.stream_status(pid) in [:reconnecting, :connecting, :connected]
    end
  end

  describe "stream_stop/1" do
    test "stops the connection via facade" do
      {:ok, pid} = MarketConnection.start_link(api_token: "test_token")

      assert Process.alive?(pid)
      ExTradier.stream_stop(pid)
      Process.sleep(50)
      refute Process.alive?(pid)
    end
  end

  describe "start_market_stream/1" do
    test "delegates to MarketConnection.start_link" do
      {:ok, pid} = ExTradier.start_market_stream(api_token: "test_token")
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

      assert Process.alive?(pid)
      assert ExTradier.stream_status(pid) == :disconnected
    end
  end

  describe "stream_subscribe/2 and stream_unsubscribe/2" do
    test "delegates to MarketConnection" do
      stub_connection_flow()
      {:ok, pid} = ExTradier.start_market_stream(api_token: "test_token")
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

      assert :ok = ExTradier.stream_subscribe(pid, ["AAPL", "MSFT"])
      Process.sleep(100)

      info = ExTradier.stream_info(pid)
      assert "AAPL" in info.symbols
      assert "MSFT" in info.symbols

      assert :ok = ExTradier.stream_unsubscribe(pid, ["MSFT"])
      Process.sleep(50)

      info = ExTradier.stream_info(pid)
      assert "AAPL" in info.symbols
      refute "MSFT" in info.symbols
    end
  end

  describe "build_stream_url/2" do
    test "delegates to Streaming.build_websocket_url" do
      url = ExTradier.build_stream_url("session-123", :market)
      assert url =~ "sessionid=session-123"
      assert url =~ "markets/events"
    end
  end
end
