defmodule ExTradier.Streaming.EmptySubscriptionTest do
  @moduledoc """
  Regression tests for the empty-symbol guard in the streaming connections.

  The guard used to be `map_size(subscribed_symbols) == 0`, which is never true
  for a `MapSet` (`map_size(MapSet.new())` is 2 — the struct's own keys), so both
  connections would open a session with no symbols subscribed.
  """
  use ExUnit.Case, async: false
  use Mimic

  alias ExTradier.Fixtures
  alias ExTradier.Streaming.{HttpConnection, MarketConnection, Session}

  setup :set_mimic_global
  setup :verify_on_exit!

  setup do
    test_pid = self()

    stub(ExTradier.Streaming, :create_market_session, fn _client, _params ->
      send(test_pid, :session_created)
      {:ok, Fixtures.streaming_session_response()}
    end)

    stub(ExTradier.Streaming, :create_session_from_response, fn _resp ->
      {:ok,
       %Session{session_id: "test-session", url: "wss://test", created_at: DateTime.utc_now()}}
    end)

    stub(ExTradier.Streaming, :session_expired?, fn _session -> false end)
    stub(ExTradier.Streaming, :time_until_expiry, fn _session -> 300_000 end)

    stub(ExTradier.Streaming.Client, :start_link, fn _url, _parent ->
      {:ok, spawn(fn -> Process.sleep(:infinity) end)}
    end)

    :ok
  end

  test "map_size/1 on a MapSet never reports zero" do
    assert map_size(MapSet.new()) != 0
    assert MapSet.size(MapSet.new()) == 0
  end

  describe "HttpConnection" do
    test "does not create a session when subscribing to no symbols" do
      {:ok, pid} = start_http()

      assert :ok = HttpConnection.subscribe(pid, [])

      refute_receive :session_created, 200
      assert HttpConnection.get_status(pid) == :disconnected
    end

    test "creates a session once symbols are subscribed" do
      {:ok, pid} = start_http()

      assert :ok = HttpConnection.subscribe(pid, ["AAPL"])

      assert_receive :session_created, 500
    end

    test "unsubscribing the last symbol leaves it disconnected" do
      {:ok, pid} = start_http()

      HttpConnection.subscribe(pid, ["AAPL"])
      assert_receive :session_created, 500

      assert :ok = HttpConnection.unsubscribe(pid, ["AAPL"])
      assert HttpConnection.get_status(pid) == :disconnected
      assert HttpConnection.get_info(pid).symbols == []
    end
  end

  describe "MarketConnection" do
    test "does not create a session when subscribing to no symbols" do
      {:ok, pid} = start_market()

      assert :ok = MarketConnection.subscribe(pid, [])

      refute_receive :session_created, 200
      assert MarketConnection.get_status(pid) == :disconnected
    end

    test "creates a session once symbols are subscribed" do
      {:ok, pid} = start_market()

      assert :ok = MarketConnection.subscribe(pid, ["AAPL"])

      assert_receive :session_created, 500
    end
  end

  defp start_http do
    {:ok, pid} = HttpConnection.start_link(api_token: "test_token")
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)
    {:ok, pid}
  end

  defp start_market do
    {:ok, pid} = MarketConnection.start_link(api_token: "test_token", auto_connect: false)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)
    {:ok, pid}
  end
end
