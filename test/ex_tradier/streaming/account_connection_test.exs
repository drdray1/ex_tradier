defmodule ExTradier.Streaming.AccountConnectionTest do
  use ExUnit.Case, async: false
  use Mimic

  alias ExTradier.Streaming.AccountConnection
  alias ExTradier.Streaming.Session
  alias ExTradier.Fixtures

  setup :set_mimic_global
  setup :verify_on_exit!

  defp start_connection(opts \\ []) do
    default_opts = [api_token: "test_token", account_id: "VA000001", auto_connect: false]
    {:ok, pid} = AccountConnection.start_link(Keyword.merge(default_opts, opts))
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)
    {:ok, pid}
  end

  defp stub_connection_flow do
    stub(ExTradier.Streaming, :create_account_session, fn _client, _account_id ->
      {:ok, Fixtures.account_session_response()}
    end)

    stub(ExTradier.Streaming, :create_session_from_response, fn _resp ->
      {:ok,
       %Session{
         session_id: "test-account-session",
         url: "wss://test",
         created_at: DateTime.utc_now()
       }}
    end)

    stub(ExTradier.Streaming, :session_expired?, fn _session -> false end)
    stub(ExTradier.Streaming, :time_until_expiry, fn _session -> 300_000 end)

    stub(ExTradier.Streaming, :build_websocket_url, fn _session_id, _type, _sandbox ->
      "wss://test/accounts/events?sessionid=test-account-session"
    end)

    stub(ExTradier.Streaming.Client, :start_link, fn _url, parent ->
      pid = spawn(fn -> Process.sleep(:infinity) end)
      send(parent, {:stream_connected, pid})
      {:ok, pid}
    end)

    stub(ExTradier.Streaming.Client, :close, fn _pid -> :ok end)
  end

  describe "start_link/1" do
    test "starts with disconnected status when auto_connect is false" do
      {:ok, pid} = start_connection()
      assert AccountConnection.get_status(pid) == :disconnected
    end
  end

  describe "get_status/1" do
    test "returns current status" do
      {:ok, pid} = start_connection()
      assert AccountConnection.get_status(pid) == :disconnected
    end
  end

  describe "get_info/1" do
    test "returns connection info with account_id" do
      {:ok, pid} = start_connection()
      info = AccountConnection.get_info(pid)

      assert info.status == :disconnected
      assert info.account_id == "VA000001"
      assert info.subscriber_count == 0
      assert info.session_valid == false
    end
  end

  describe "add_subscriber/2 and remove_subscriber/2" do
    test "tracks subscriber count" do
      {:ok, pid} = start_connection()
      subscriber = spawn(fn -> Process.sleep(:infinity) end)

      AccountConnection.add_subscriber(pid, subscriber)
      Process.sleep(50)
      assert AccountConnection.get_info(pid).subscriber_count == 1

      AccountConnection.remove_subscriber(pid, subscriber)
      Process.sleep(50)
      assert AccountConnection.get_info(pid).subscriber_count == 0

      Process.exit(subscriber, :kill)
    end
  end

  describe "connect/1" do
    test "initiates connection to streaming API" do
      stub_connection_flow()
      {:ok, pid} = start_connection()
      assert AccountConnection.get_status(pid) == :disconnected

      AccountConnection.connect(pid)
      Process.sleep(100)
      assert AccountConnection.get_status(pid) == :connected
    end
  end

  describe "reconnect/1" do
    test "triggers reconnection" do
      stub_connection_flow()
      {:ok, pid} = start_connection()

      AccountConnection.connect(pid)
      Process.sleep(100)
      assert AccountConnection.get_status(pid) == :connected

      AccountConnection.reconnect(pid)
      Process.sleep(50)
      assert AccountConnection.get_status(pid) in [:reconnecting, :connecting, :connected]
    end
  end

  describe "stop/1" do
    test "stops the process" do
      {:ok, pid} =
        AccountConnection.start_link(
          api_token: "test_token",
          account_id: "VA000001",
          auto_connect: false
        )

      assert Process.alive?(pid)
      AccountConnection.stop(pid)
      Process.sleep(50)
      refute Process.alive?(pid)
    end
  end

  describe "subscriber DOWN monitoring" do
    test "removes subscriber when process dies" do
      {:ok, pid} = start_connection()
      subscriber = spawn(fn -> Process.sleep(:infinity) end)

      AccountConnection.add_subscriber(pid, subscriber)
      Process.sleep(50)
      assert AccountConnection.get_info(pid).subscriber_count == 1

      Process.exit(subscriber, :kill)
      Process.sleep(100)
      assert AccountConnection.get_info(pid).subscriber_count == 0
    end
  end

  describe "stream message broadcasting" do
    test "broadcasts account events to subscribers" do
      stub_connection_flow()

      stub(ExTradier.Streaming, :parse_event, fn _msg ->
        {:ok, %{"type" => "order", "status" => "filled"}}
      end)

      {:ok, pid} = start_connection()
      AccountConnection.add_subscriber(pid, self())
      AccountConnection.connect(pid)
      Process.sleep(100)

      ws_pid = get_ws_pid(pid)
      send(pid, {:stream_message, ws_pid, ~s({"type":"order","status":"filled"})})

      assert_receive {:account_event, %{"type" => "order", "status" => "filled"}}, 500
    end

    test "handles parse errors gracefully" do
      stub_connection_flow()

      stub(ExTradier.Streaming, :parse_event, fn _msg ->
        {:error, :invalid_json}
      end)

      {:ok, pid} = start_connection()
      AccountConnection.connect(pid)
      Process.sleep(100)

      ws_pid = get_ws_pid(pid)
      send(pid, {:stream_message, ws_pid, "bad data"})
      Process.sleep(50)

      assert Process.alive?(pid)
    end
  end

  describe "stream disconnection" do
    test "triggers reconnect on disconnect" do
      stub_connection_flow()
      {:ok, pid} = start_connection()

      AccountConnection.connect(pid)
      Process.sleep(100)
      assert AccountConnection.get_status(pid) == :connected

      ws_pid = get_ws_pid(pid)
      send(pid, {:stream_disconnected, ws_pid, :normal})
      Process.sleep(50)

      assert AccountConnection.get_status(pid) in [:disconnected, :reconnecting]
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
      stub(ExTradier.Streaming, :create_account_session, fn _client, _account_id ->
        {:error, :connection_refused}
      end)

      {:ok, pid} = start_connection()
      AccountConnection.connect(pid)
      Process.sleep(100)

      assert AccountConnection.get_status(pid) in [:disconnected, :reconnecting]
    end

    test "schedules reconnect when session response is invalid" do
      stub(ExTradier.Streaming, :create_account_session, fn _client, _account_id ->
        {:ok, %{"invalid" => "response"}}
      end)

      stub(ExTradier.Streaming, :create_session_from_response, fn _resp ->
        {:error, :invalid_response}
      end)

      {:ok, pid} = start_connection()
      AccountConnection.connect(pid)
      Process.sleep(100)

      assert AccountConnection.get_status(pid) in [:disconnected, :reconnecting]
    end
  end

  describe "websocket connection failure" do
    test "schedules reconnect when websocket fails to start" do
      stub(ExTradier.Streaming, :create_account_session, fn _client, _account_id ->
        {:ok, Fixtures.account_session_response()}
      end)

      stub(ExTradier.Streaming, :create_session_from_response, fn _resp ->
        {:ok,
         %Session{
           session_id: "test-account-session",
           url: "wss://test",
           created_at: DateTime.utc_now()
         }}
      end)

      stub(ExTradier.Streaming, :session_expired?, fn _session -> false end)

      stub(ExTradier.Streaming, :build_websocket_url, fn _session_id, _type, _sandbox ->
        "wss://test/accounts/events?sessionid=test-account-session"
      end)

      stub(ExTradier.Streaming.Client, :start_link, fn _url, _parent ->
        {:error, :connection_refused}
      end)

      {:ok, pid} = start_connection()
      AccountConnection.connect(pid)
      Process.sleep(100)

      assert AccountConnection.get_status(pid) in [:disconnected, :reconnecting]
    end
  end

  describe "auto_connect: true" do
    test "attempts to connect on startup" do
      stub_connection_flow()

      {:ok, pid} =
        AccountConnection.start_link(
          api_token: "test_token",
          account_id: "VA000001",
          auto_connect: true
        )

      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

      Process.sleep(100)
      assert AccountConnection.get_status(pid) == :connected
    end
  end

  describe "reconnect timer" do
    test "reconnect message triggers do_connect" do
      stub_connection_flow()
      {:ok, pid} = start_connection()

      AccountConnection.connect(pid)
      Process.sleep(100)
      assert AccountConnection.get_status(pid) == :connected

      # Disconnect, then send :reconnect directly
      ws_pid = get_ws_pid(pid)
      send(pid, {:stream_disconnected, ws_pid, :normal})
      Process.sleep(50)

      send(pid, :reconnect)
      Process.sleep(100)

      assert AccountConnection.get_status(pid) in [:connecting, :connected]
    end
  end

  describe "session refresh" do
    test "refresh_session message triggers session refresh" do
      stub_connection_flow()
      {:ok, pid} = start_connection()

      AccountConnection.connect(pid)
      Process.sleep(100)
      assert AccountConnection.get_status(pid) == :connected

      send(pid, :refresh_session)
      Process.sleep(100)

      assert Process.alive?(pid)
      assert AccountConnection.get_status(pid) == :connected
    end
  end

  describe "connect guards" do
    test "connect when already connected is a no-op" do
      stub_connection_flow()
      {:ok, pid} = start_connection()

      AccountConnection.connect(pid)
      Process.sleep(100)
      assert AccountConnection.get_status(pid) == :connected

      # Connect again while already connected
      AccountConnection.connect(pid)
      Process.sleep(50)
      assert AccountConnection.get_status(pid) == :connected
    end
  end

  describe "terminate with active websocket" do
    test "closes websocket on terminate" do
      stub_connection_flow()
      {:ok, pid} = start_connection()

      AccountConnection.connect(pid)
      Process.sleep(100)
      assert AccountConnection.get_status(pid) == :connected

      AccountConnection.stop(pid)
      Process.sleep(50)
      refute Process.alive?(pid)
    end
  end

  describe "start_link/1 with name" do
    test "registers process with name" do
      name = :"test_account_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        AccountConnection.start_link(
          api_token: "test_token",
          account_id: "VA000001",
          auto_connect: false,
          name: name
        )

      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

      assert Process.whereis(name) == pid
      assert AccountConnection.get_status(name) == :disconnected
    end
  end

  defp get_ws_pid(connection_pid) do
    state = :sys.get_state(connection_pid)
    state.websocket_pid
  end
end
