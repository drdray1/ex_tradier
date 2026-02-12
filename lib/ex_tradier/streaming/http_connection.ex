defmodule ExTradier.Streaming.HttpConnection do
  @moduledoc """
  GenServer managing a Tradier HTTP streaming connection for market data.

  Provides an alternative to WebSocket streaming using a long-lived HTTP
  connection with newline-delimited JSON. Follows the same subscriber
  broadcasting pattern as `MarketConnection`.

  ## Usage

      {:ok, pid} = HttpConnection.start_link(api_token: "your_token")
      HttpConnection.add_subscriber(pid, self())
      HttpConnection.subscribe(pid, ["AAPL", "MSFT"])

      # You'll receive messages like:
      # {:stream_event, %ExTradier.Streaming.QuoteEvent{...}}
  """

  use GenServer

  require Logger

  alias ExTradier.Streaming
  alias ExTradier.Streaming.Session

  @default_filters ["quote", "trade", "summary"]
  @session_refresh_buffer_ms 60_000
  @reconnect_base_delay_ms 1_000
  @reconnect_max_delay_ms 30_000
  @max_reconnect_attempts 10

  defmodule State do
    @moduledoc false
    defstruct [
      :api_token,
      :sandbox_mode,
      :client,
      :session,
      :stream_pid,
      :buffer,
      :subscribed_symbols,
      :filters,
      :subscribers,
      :status,
      :reconnect_attempts,
      :reconnect_timer,
      :session_refresh_timer
    ]

    @type status :: :disconnected | :connecting | :connected | :reconnecting

    @type t :: %__MODULE__{
            api_token: String.t(),
            sandbox_mode: boolean(),
            client: Req.Request.t() | nil,
            session: Session.t() | nil,
            stream_pid: pid() | nil,
            buffer: String.t(),
            subscribed_symbols: MapSet.t(),
            filters: [String.t()],
            subscribers: MapSet.t(),
            status: status(),
            reconnect_attempts: non_neg_integer(),
            reconnect_timer: reference() | nil,
            session_refresh_timer: reference() | nil
          }
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts an HttpConnection process.

  ## Options

    - `:api_token` - Required. The Tradier API token
    - `:sandbox_mode` - Optional. Use sandbox environment (default: false)
    - `:filters` - Optional. Event types to subscribe to (default: ["quote", "trade", "summary"])
    - `:name` - Optional. Process name for registration
  """
  def start_link(opts) do
    api_token = Keyword.fetch!(opts, :api_token)
    sandbox_mode = Keyword.get(opts, :sandbox_mode, false)
    filters = Keyword.get(opts, :filters, @default_filters)
    name = Keyword.get(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, {api_token, sandbox_mode, filters}, gen_opts)
  end

  @doc """
  Subscribes to symbols for streaming.
  """
  def subscribe(server, symbols) when is_list(symbols) do
    GenServer.call(server, {:subscribe, symbols})
  end

  @doc """
  Unsubscribes from symbols.
  """
  def unsubscribe(server, symbols) when is_list(symbols) do
    GenServer.call(server, {:unsubscribe, symbols})
  end

  @doc """
  Registers a process to receive streaming events.
  Events are sent as `{:stream_event, event}` messages.
  """
  def add_subscriber(server, subscriber_pid) when is_pid(subscriber_pid) do
    GenServer.cast(server, {:add_subscriber, subscriber_pid})
  end

  @doc """
  Unregisters a process from receiving events.
  """
  def remove_subscriber(server, subscriber_pid) when is_pid(subscriber_pid) do
    GenServer.cast(server, {:remove_subscriber, subscriber_pid})
  end

  @doc """
  Gets the current connection status.
  """
  def get_status(server) do
    GenServer.call(server, :get_status)
  end

  @doc """
  Gets information about the current connection.
  """
  def get_info(server) do
    GenServer.call(server, :get_info)
  end

  @doc """
  Forces a reconnection.
  """
  def reconnect(server) do
    GenServer.cast(server, :reconnect)
  end

  @doc """
  Stops the connection gracefully.
  """
  def stop(server) do
    GenServer.stop(server, :normal)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init({api_token, sandbox_mode, filters}) do
    state = %State{
      api_token: api_token,
      sandbox_mode: sandbox_mode,
      client: ExTradier.Client.new(api_token, sandbox: sandbox_mode),
      session: nil,
      stream_pid: nil,
      buffer: "",
      subscribed_symbols: MapSet.new(),
      filters: filters,
      subscribers: MapSet.new(),
      status: :disconnected,
      reconnect_attempts: 0,
      reconnect_timer: nil,
      session_refresh_timer: nil
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:subscribe, symbols}, _from, state) do
    new_symbols = MapSet.new(symbols)
    updated_symbols = MapSet.union(state.subscribed_symbols, new_symbols)
    state = %{state | subscribed_symbols: updated_symbols}

    {:reply, :ok, maybe_connect(state)}
  end

  @impl GenServer
  def handle_call({:unsubscribe, symbols}, _from, state) do
    remove_symbols = MapSet.new(symbols)
    updated_symbols = MapSet.difference(state.subscribed_symbols, remove_symbols)
    state = %{state | subscribed_symbols: updated_symbols}

    if MapSet.size(updated_symbols) == 0 do
      {:reply, :ok, disconnect(state)}
    else
      # Reconnect with updated symbols
      state = disconnect(state)
      {:reply, :ok, maybe_connect(state)}
    end
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  @impl GenServer
  def handle_call(:get_info, _from, state) do
    info = %{
      status: state.status,
      symbols: MapSet.to_list(state.subscribed_symbols),
      subscriber_count: MapSet.size(state.subscribers),
      session_valid: state.session != nil and not Streaming.session_expired?(state.session),
      transport: :http
    }

    {:reply, info, state}
  end

  @impl GenServer
  def handle_cast({:add_subscriber, pid}, state) do
    Process.monitor(pid)
    {:noreply, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_cast({:remove_subscriber, pid}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_cast(:reconnect, state) do
    state = disconnect(state)
    {:noreply, schedule_reconnect(state)}
  end

  @impl GenServer
  def handle_info({:http_chunk, chunk}, state) do
    {events, remaining} = parse_buffer(state.buffer <> chunk)

    for event <- events do
      broadcast_event(state.subscribers, event)
    end

    {:noreply, %{state | buffer: remaining}}
  end

  @impl GenServer
  def handle_info({:http_stream_connected, pid}, %{stream_pid: pid} = state) do
    Logger.info("[HttpConnection] Stream connected")

    state = %{state | status: :connected, reconnect_attempts: 0}
    state = schedule_session_refresh(state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:http_stream_ended, pid, reason}, %{stream_pid: pid} = state) do
    Logger.warning("[HttpConnection] Stream ended: #{inspect(reason)}")
    state = %{state | stream_pid: nil, status: :disconnected, buffer: ""}
    {:noreply, schedule_reconnect(state)}
  end

  @impl GenServer
  def handle_info(:reconnect, state) do
    Logger.info(
      "[HttpConnection] Attempting to reconnect (attempt #{state.reconnect_attempts + 1})"
    )

    {:noreply, do_connect(%{state | reconnect_timer: nil})}
  end

  @impl GenServer
  def handle_info(:refresh_session, state) do
    Logger.info("[HttpConnection] Refreshing session")
    state = disconnect(%{state | session_refresh_timer: nil})
    {:noreply, do_connect(state)}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logger.debug("[HttpConnection] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    cancel_timer(state.reconnect_timer)
    cancel_timer(state.session_refresh_timer)
    kill_stream(state.stream_pid)
    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp maybe_connect(%{status: :connected} = state), do: state
  defp maybe_connect(%{status: :connecting} = state), do: state

  defp maybe_connect(%{subscribed_symbols: symbols} = state)
       when map_size(symbols) == 0,
       do: state

  defp maybe_connect(state), do: do_connect(state)

  defp do_connect(state) do
    state = %{state | status: :connecting}

    case create_or_refresh_session(state) do
      {:ok, session, state} ->
        start_stream(session, state)

      {:error, reason} ->
        Logger.error("[HttpConnection] Failed to create session: #{inspect(reason)}")
        schedule_reconnect(%{state | status: :disconnected})
    end
  end

  defp create_or_refresh_session(%{session: nil} = state) do
    create_session(state)
  end

  defp create_or_refresh_session(%{session: session} = state) do
    if Streaming.session_expired?(session) do
      create_session(state)
    else
      {:ok, session, state}
    end
  end

  defp create_session(state) do
    symbols = MapSet.to_list(state.subscribed_symbols)

    params = %{
      symbols: symbols,
      filter: state.filters
    }

    case Streaming.create_market_session(state.client, params) do
      {:ok, response} ->
        case Streaming.create_session_from_response(response) do
          {:ok, session} ->
            {:ok, session, %{state | session: session}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_stream(session, state) do
    parent = self()
    symbols = MapSet.to_list(state.subscribed_symbols)
    symbols_str = Enum.join(symbols, ",")
    filters_str = Enum.join(state.filters, ",")

    stream_url = ExTradier.Client.stream_url(state.sandbox_mode)

    pid =
      spawn_link(fn ->
        do_http_stream(parent, stream_url, session.session_id, symbols_str, filters_str,
          api_token: state.api_token
        )
      end)

    %{state | stream_pid: pid}
  end

  defp do_http_stream(parent, base_url, session_id, symbols, filters, opts) do
    api_token = Keyword.fetch!(opts, :api_token)

    req =
      Req.new(
        url: "#{base_url}/markets/events",
        headers: [
          {"authorization", "Bearer #{api_token}"},
          {"accept", "application/json"}
        ],
        params: [
          sessionid: session_id,
          symbols: symbols,
          filter: filters,
          linebreak: true
        ],
        # Disable retries for streaming - the GenServer handles reconnection
        retry: false,
        # Long receive timeout for streaming
        receive_timeout: :infinity
      )

    send(parent, {:http_stream_connected, self()})

    try do
      Req.get!(req,
        into: fn {:data, chunk}, {req_ref, resp} ->
          send(parent, {:http_chunk, chunk})
          {:cont, {req_ref, resp}}
        end
      )

      send(parent, {:http_stream_ended, self(), :normal})
    rescue
      e ->
        send(parent, {:http_stream_ended, self(), {:error, Exception.message(e)}})
    end
  end

  @doc false
  def parse_buffer(buffer) do
    lines = String.split(buffer, "\n")
    {complete_lines, [remaining]} = Enum.split(lines, -1)

    events =
      complete_lines
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.flat_map(&parse_line/1)

    {events, remaining}
  end

  defp parse_line(line) do
    case Streaming.parse_typed_event(line) do
      {:ok, event} -> [event]
      _ -> []
    end
  end

  defp broadcast_event(subscribers, event) do
    Enum.each(subscribers, fn pid ->
      send(pid, {:stream_event, event})
    end)
  end

  defp schedule_reconnect(state) when state.reconnect_attempts >= @max_reconnect_attempts do
    Logger.error("[HttpConnection] Max reconnect attempts reached")
    %{state | status: :disconnected}
  end

  defp schedule_reconnect(state) do
    cancel_timer(state.reconnect_timer)

    delay = calculate_backoff_delay(state.reconnect_attempts)
    timer = Process.send_after(self(), :reconnect, delay)

    Logger.info("[HttpConnection] Scheduling reconnect in #{delay}ms")

    %{
      state
      | reconnect_timer: timer,
        reconnect_attempts: state.reconnect_attempts + 1,
        status: :reconnecting
    }
  end

  defp calculate_backoff_delay(attempts) do
    delay = @reconnect_base_delay_ms * :math.pow(2, attempts)
    min(round(delay), @reconnect_max_delay_ms)
  end

  defp schedule_session_refresh(state) do
    cancel_timer(state.session_refresh_timer)

    if state.session do
      time_until_expiry = Streaming.time_until_expiry(state.session)
      refresh_in = max(0, time_until_expiry - @session_refresh_buffer_ms)
      timer = Process.send_after(self(), :refresh_session, refresh_in)

      Logger.debug("[HttpConnection] Scheduling session refresh in #{refresh_in}ms")
      %{state | session_refresh_timer: timer}
    else
      state
    end
  end

  defp disconnect(state) do
    cancel_timer(state.reconnect_timer)
    cancel_timer(state.session_refresh_timer)
    kill_stream(state.stream_pid)

    %{
      state
      | stream_pid: nil,
        session: nil,
        status: :disconnected,
        buffer: "",
        reconnect_timer: nil,
        session_refresh_timer: nil
    }
  end

  defp kill_stream(nil), do: :ok

  defp kill_stream(pid) do
    if Process.alive?(pid) do
      Process.unlink(pid)
      Process.exit(pid, :shutdown)
    end
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)
end
