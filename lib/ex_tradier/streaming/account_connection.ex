defmodule ExTradier.Streaming.AccountConnection do
  @moduledoc """
  GenServer managing a Tradier account events streaming WebSocket connection.

  Handles streaming of account-level events such as order status updates,
  trade executions, and account balance changes.

  ## Usage

      {:ok, pid} = AccountConnection.start_link(
        api_token: "your_token",
        account_id: "VA000001"
      )

      AccountConnection.add_subscriber(pid, self())

      # You'll receive messages like:
      # {:account_event, %{type: "order_status", ...}}
  """

  use GenServer

  require Logger

  alias ExTradier.Streaming
  alias ExTradier.Streaming.Session

  @session_refresh_buffer_ms 60_000
  @reconnect_base_delay_ms 1_000
  @reconnect_max_delay_ms 30_000
  @max_reconnect_attempts 10

  defmodule State do
    @moduledoc false
    defstruct [
      :api_token,
      :account_id,
      :sandbox_mode,
      :client,
      :session,
      :websocket_pid,
      :subscribers,
      :status,
      :reconnect_attempts,
      :reconnect_timer,
      :session_refresh_timer
    ]

    @type status :: :disconnected | :connecting | :connected | :reconnecting

    @type t :: %__MODULE__{
            api_token: String.t(),
            account_id: String.t(),
            sandbox_mode: boolean(),
            client: Req.Request.t() | nil,
            session: Session.t() | nil,
            websocket_pid: pid() | nil,
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
  Starts an AccountConnection process.

  ## Options

    - `:api_token` - Required. The Tradier API token
    - `:account_id` - Required. The account ID to stream events for
    - `:sandbox_mode` - Optional. Use sandbox environment (default: false)
    - `:auto_connect` - Optional. Whether to connect immediately (default: true)
    - `:name` - Optional. Process name for registration
  """
  def start_link(opts) do
    api_token = Keyword.fetch!(opts, :api_token)
    account_id = Keyword.fetch!(opts, :account_id)
    sandbox_mode = Keyword.get(opts, :sandbox_mode, false)
    auto_connect = Keyword.get(opts, :auto_connect, true)
    name = Keyword.get(opts, :name)

    gen_opts = if name, do: [name: name], else: []

    GenServer.start_link(
      __MODULE__,
      {api_token, account_id, sandbox_mode, auto_connect},
      gen_opts
    )
  end

  @doc """
  Registers a process to receive account events.
  Events are sent as `{:account_event, event}` messages.
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
  Initiates connection to the streaming API.
  """
  def connect(server) do
    GenServer.cast(server, :connect)
  end

  @doc """
  Forces a reconnection to the WebSocket.
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
  def init({api_token, account_id, sandbox_mode, auto_connect}) do
    state = %State{
      api_token: api_token,
      account_id: account_id,
      sandbox_mode: sandbox_mode,
      client: ExTradier.Client.new(api_token, sandbox: sandbox_mode),
      session: nil,
      websocket_pid: nil,
      subscribers: MapSet.new(),
      status: :disconnected,
      reconnect_attempts: 0,
      reconnect_timer: nil,
      session_refresh_timer: nil
    }

    if auto_connect do
      {:ok, state, {:continue, :connect}}
    else
      {:ok, state}
    end
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    {:noreply, do_connect(state)}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  @impl GenServer
  def handle_call(:get_info, _from, state) do
    info = %{
      status: state.status,
      account_id: state.account_id,
      subscriber_count: MapSet.size(state.subscribers),
      session_valid: state.session != nil and not Streaming.session_expired?(state.session)
    }

    {:reply, info, state}
  end

  @impl GenServer
  def handle_cast(:connect, state) do
    {:noreply, do_connect(state)}
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
  def handle_info({:stream_connected, ws_pid}, %{websocket_pid: ws_pid} = state) do
    Logger.info("[AccountConnection] WebSocket connected for account #{state.account_id}")

    state = %{state | status: :connected, reconnect_attempts: 0}
    state = schedule_session_refresh(state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:stream_message, ws_pid, message}, %{websocket_pid: ws_pid} = state) do
    case Streaming.parse_event(message) do
      {:ok, event} ->
        broadcast_event(state.subscribers, event)

      {:error, reason} ->
        Logger.debug("[AccountConnection] Failed to parse message: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:stream_disconnected, ws_pid, reason}, %{websocket_pid: ws_pid} = state) do
    Logger.warning("[AccountConnection] WebSocket disconnected: #{inspect(reason)}")
    state = %{state | websocket_pid: nil, status: :disconnected}
    {:noreply, schedule_reconnect(state)}
  end

  @impl GenServer
  def handle_info(:reconnect, state) do
    Logger.info(
      "[AccountConnection] Attempting to reconnect (attempt #{state.reconnect_attempts + 1})"
    )

    {:noreply, do_connect(%{state | reconnect_timer: nil})}
  end

  @impl GenServer
  def handle_info(:refresh_session, state) do
    Logger.info("[AccountConnection] Refreshing session")
    state = %{state | session_refresh_timer: nil}
    {:noreply, refresh_session(state)}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logger.debug("[AccountConnection] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    cancel_timer(state.reconnect_timer)
    cancel_timer(state.session_refresh_timer)

    if state.websocket_pid do
      ExTradier.Streaming.Client.close(state.websocket_pid)
    end

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_connect(%{status: :connected} = state), do: state
  defp do_connect(%{status: :connecting} = state), do: state

  defp do_connect(state) do
    state = %{state | status: :connecting}

    case create_or_refresh_session(state) do
      {:ok, session, state} ->
        connect_websocket(session, state)

      {:error, reason} ->
        Logger.error("[AccountConnection] Failed to create session: #{inspect(reason)}")
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
    case Streaming.create_account_session(state.client, state.account_id) do
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

  defp connect_websocket(session, state) do
    url = Streaming.build_websocket_url(session.session_id, :account, state.sandbox_mode)

    case ExTradier.Streaming.Client.start_link(url, self()) do
      {:ok, ws_pid} ->
        %{state | websocket_pid: ws_pid}

      {:error, reason} ->
        Logger.error("[AccountConnection] Failed to connect WebSocket: #{inspect(reason)}")
        schedule_reconnect(%{state | status: :disconnected})
    end
  end

  defp broadcast_event(subscribers, event) do
    Enum.each(subscribers, fn pid ->
      send(pid, {:account_event, event})
    end)
  end

  defp schedule_reconnect(state) when state.reconnect_attempts >= @max_reconnect_attempts do
    Logger.error("[AccountConnection] Max reconnect attempts reached")
    %{state | status: :disconnected}
  end

  defp schedule_reconnect(state) do
    cancel_timer(state.reconnect_timer)

    delay = calculate_backoff_delay(state.reconnect_attempts)
    timer = Process.send_after(self(), :reconnect, delay)

    Logger.info("[AccountConnection] Scheduling reconnect in #{delay}ms")

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

      Logger.debug("[AccountConnection] Scheduling session refresh in #{refresh_in}ms")
      %{state | session_refresh_timer: timer}
    else
      state
    end
  end

  defp refresh_session(state) do
    case create_session(state) do
      {:ok, session, state} ->
        Logger.info("[AccountConnection] Session refreshed successfully")
        schedule_session_refresh(%{state | session: session})

      {:error, reason} ->
        Logger.error("[AccountConnection] Failed to refresh session: #{inspect(reason)}")
        GenServer.cast(self(), :reconnect)
        state
    end
  end

  defp disconnect(state) do
    cancel_timer(state.reconnect_timer)
    cancel_timer(state.session_refresh_timer)

    if state.websocket_pid do
      ExTradier.Streaming.Client.close(state.websocket_pid)
    end

    %{
      state
      | websocket_pid: nil,
        session: nil,
        status: :disconnected,
        reconnect_timer: nil,
        session_refresh_timer: nil
    }
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)
end
