defmodule ExTradier.TelemetryTest do
  # `:telemetry` handlers are global, so an async test running alongside this one
  # would deliver its own request events into these assertions.
  use ExUnit.Case, async: false

  alias ExTradier.{Client, Fixtures}

  setup context do
    events = [
      [:ex_tradier, :request, :start],
      [:ex_tradier, :request, :stop],
      [:ex_tradier, :request, :exception]
    ]

    handler_id = "test-#{inspect(context.test)}"

    :telemetry.attach_many(handler_id, events, &__MODULE__.forward_event/4, self())
    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  @doc false
  def forward_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry, event, measurements, metadata})
  end

  describe "request lifecycle" do
    test "emits start and stop around a successful request" do
      Req.Test.expect(ExTradier.TelemetryTest.Ok, fn conn ->
        Req.Test.json(conn, Fixtures.profile_response())
      end)

      client = Fixtures.test_client(ExTradier.TelemetryTest.Ok)
      assert {:ok, _} = ExTradier.User.get_profile(client)

      assert_receive {:telemetry, [:ex_tradier, :request, :start], start_measurements,
                      start_metadata}

      assert is_integer(start_measurements.system_time)
      assert start_metadata.method == :get
      assert start_metadata.url =~ "/user/profile"
      assert start_metadata.sandbox == true

      assert_receive {:telemetry, [:ex_tradier, :request, :stop], stop_measurements,
                      stop_metadata}

      assert is_integer(stop_measurements.duration)
      assert stop_measurements.duration >= 0
      assert stop_metadata.status == 200
      assert stop_metadata.method == :get
    end

    test "reports the production environment in metadata" do
      Req.Test.expect(ExTradier.TelemetryTest.Prod, fn conn ->
        Req.Test.json(conn, Fixtures.clock_response())
      end)

      client =
        Client.new("token",
          sandbox: false,
          plug: {Req.Test, ExTradier.TelemetryTest.Prod}
        )

      assert {:ok, _} = ExTradier.MarketData.get_clock(client)

      assert_receive {:telemetry, [:ex_tradier, :request, :start], _, %{sandbox: false}}
    end

    test "includes parsed rate limit headers in stop metadata" do
      Req.Test.expect(ExTradier.TelemetryTest.RateLimit, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-ratelimit-allowed", "120")
        |> Plug.Conn.put_resp_header("x-ratelimit-available", "119")
        |> Plug.Conn.put_resp_header("x-ratelimit-used", "1")
        |> Plug.Conn.put_resp_header("x-ratelimit-expiry", "1705084860000")
        |> Req.Test.json(Fixtures.clock_response())
      end)

      client = Fixtures.test_client(ExTradier.TelemetryTest.RateLimit)
      assert {:ok, _} = ExTradier.MarketData.get_clock(client)

      assert_receive {:telemetry, [:ex_tradier, :request, :stop], _, metadata}

      assert metadata.rate_limit == %{
               allowed: 120,
               available: 119,
               used: 1,
               expiry: 1_705_084_860_000
             }
    end

    test "sets rate_limit to nil when Tradier sends no rate limit headers" do
      Req.Test.expect(ExTradier.TelemetryTest.NoRateLimit, fn conn ->
        Req.Test.json(conn, Fixtures.clock_response())
      end)

      client = Fixtures.test_client(ExTradier.TelemetryTest.NoRateLimit)
      assert {:ok, _} = ExTradier.MarketData.get_clock(client)

      assert_receive {:telemetry, [:ex_tradier, :request, :stop], _, %{rate_limit: nil}}
    end

    test "emits stop with the error status for a failed request" do
      Req.Test.expect(ExTradier.TelemetryTest.Unauthorized, fn conn ->
        Plug.Conn.send_resp(conn, 401, "")
      end)

      client = Fixtures.test_client(ExTradier.TelemetryTest.Unauthorized)
      assert {:error, :unauthorized} = ExTradier.User.get_profile(client)

      assert_receive {:telemetry, [:ex_tradier, :request, :stop], _, %{status: 401}}
    end

    test "emits an exception event on transport failure" do
      Req.Test.expect(ExTradier.TelemetryTest.Down, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      client =
        Client.new("token",
          retry: false,
          plug: {Req.Test, ExTradier.TelemetryTest.Down}
        )

      assert {:error, _} = ExTradier.User.get_profile(client)

      assert_receive {:telemetry, [:ex_tradier, :request, :exception], measurements, metadata}

      assert is_integer(measurements.duration)
      assert metadata.kind == :error
      assert %Req.TransportError{reason: :econnrefused} = metadata.reason
      assert metadata.stacktrace == []
    end
  end

  describe "telemetry: false" do
    test "emits no events" do
      Req.Test.expect(ExTradier.TelemetryTest.Disabled, fn conn ->
        Req.Test.json(conn, Fixtures.profile_response())
      end)

      client =
        Client.new("token",
          telemetry: false,
          plug: {Req.Test, ExTradier.TelemetryTest.Disabled}
        )

      assert {:ok, _} = ExTradier.User.get_profile(client)

      refute_receive {:telemetry, _, _, _}, 100
    end
  end
end
