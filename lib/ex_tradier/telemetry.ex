defmodule ExTradier.Telemetry do
  @moduledoc """
  `:telemetry` instrumentation for Tradier HTTP requests.

  Attached automatically by `ExTradier.Client.new/2`. Disable with
  `ExTradier.Client.new(token, telemetry: false)`.

  ## Events

  ### `[:ex_tradier, :request, :start]`

  Emitted just before the request is sent to the adapter.

    * Measurements — `:system_time` (`System.system_time/0`)
    * Metadata — `:method`, `:url`, `:sandbox`

  ### `[:ex_tradier, :request, :stop]`

  Emitted once a response has been received and decoded. Retried attempts do not
  emit a `:stop` event of their own; only the final response does.

    * Measurements — `:duration` (native time units)
    * Metadata — `:method`, `:url`, `:sandbox`, `:status`, `:rate_limit`

  `:rate_limit` is the result of `ExTradier.Client.extract_rate_limit/1` for the
  response, or `nil` when Tradier sent no rate limit headers.

  ### `[:ex_tradier, :request, :exception]`

  Emitted when the request fails at the transport level (connection refused,
  timeout, and similar).

    * Measurements — `:duration` (native time units)
    * Metadata — `:method`, `:url`, `:sandbox`, `:kind` (always `:error`),
      `:reason` (the exception), `:stacktrace` (always `[]`)

  ## Example

      :telemetry.attach(
        "log-tradier-requests",
        [:ex_tradier, :request, :stop],
        fn _event, %{duration: duration}, meta, _config ->
          ms = System.convert_time_unit(duration, :native, :millisecond)
          Logger.info("tradier \#{meta.method} \#{meta.url} -> \#{meta.status} in \#{ms}ms")
        end,
        nil
      )
  """

  alias ExTradier.Client

  @start_time_key :ex_tradier_start_time

  @doc """
  Attaches telemetry steps to a `Req.Request`.

  The start step is appended so that it runs immediately before the adapter, and
  the stop step is appended so that it runs after retries and body decoding.
  """
  @spec attach(Req.Request.t()) :: Req.Request.t()
  def attach(%Req.Request{} = request) do
    request
    |> Req.Request.append_request_steps(ex_tradier_telemetry: &emit_start/1)
    |> Req.Request.append_response_steps(ex_tradier_telemetry: &emit_stop/1)
    |> Req.Request.append_error_steps(ex_tradier_telemetry: &emit_exception/1)
  end

  defp emit_start(request) do
    :telemetry.execute(
      [:ex_tradier, :request, :start],
      %{system_time: System.system_time()},
      metadata(request)
    )

    Req.Request.put_private(request, @start_time_key, System.monotonic_time())
  end

  defp emit_stop({request, %Req.Response{} = response}) do
    :telemetry.execute(
      [:ex_tradier, :request, :stop],
      %{duration: duration(request)},
      request
      |> metadata()
      |> Map.merge(%{
        status: response.status,
        rate_limit: Client.extract_rate_limit(response.headers)
      })
    )

    {request, response}
  end

  defp emit_exception({request, exception}) do
    :telemetry.execute(
      [:ex_tradier, :request, :exception],
      %{duration: duration(request)},
      request
      |> metadata()
      |> Map.merge(%{kind: :error, reason: exception, stacktrace: []})
    )

    {request, exception}
  end

  defp duration(request) do
    case Req.Request.get_private(request, @start_time_key) do
      nil -> 0
      start -> System.monotonic_time() - start
    end
  end

  defp metadata(request) do
    %{
      method: request.method,
      url: URI.to_string(request.url),
      sandbox: Req.Request.get_private(request, :ex_tradier_sandbox)
    }
  end
end
