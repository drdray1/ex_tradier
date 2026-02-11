defmodule ExTradier.Streaming do
  @moduledoc """
  Tradier Streaming API - Real-time market data via WebSocket.

  Tradier uses a two-step process for streaming:
  1. Create a streaming session via REST API to get a session ID and WebSocket URL
  2. Connect to the WebSocket with the session ID to receive real-time data

  Sessions expire after 5 minutes of inactivity.
  """

  alias ExTradier.Client

  # Session expiry time in milliseconds (5 minutes)
  @session_expiry_ms 5 * 60 * 1000

  @type event_type :: :quote | :trade | :summary | :timesale

  # Typed event structs
  defmodule QuoteEvent do
    @moduledoc "Parsed quote event from streaming API"
    defstruct [
      :symbol,
      :bid,
      :bid_size,
      :bid_exchange,
      :bid_date,
      :ask,
      :ask_size,
      :ask_exchange,
      :ask_date
    ]

    @type t :: %__MODULE__{
            symbol: String.t(),
            bid: float() | nil,
            bid_size: integer() | nil,
            bid_exchange: String.t() | nil,
            bid_date: integer() | nil,
            ask: float() | nil,
            ask_size: integer() | nil,
            ask_exchange: String.t() | nil,
            ask_date: integer() | nil
          }
  end

  defmodule TradeEvent do
    @moduledoc "Parsed trade event from streaming API"
    defstruct [:symbol, :price, :size, :exchange, :cvol, :date, :last]

    @type t :: %__MODULE__{
            symbol: String.t(),
            price: float() | nil,
            size: integer() | nil,
            exchange: String.t() | nil,
            cvol: integer() | nil,
            date: integer() | nil,
            last: float() | nil
          }
  end

  defmodule SummaryEvent do
    @moduledoc "Parsed summary/OHLC event from streaming API"
    defstruct [:symbol, :open, :high, :low, :prev_close]

    @type t :: %__MODULE__{
            symbol: String.t(),
            open: float() | nil,
            high: float() | nil,
            low: float() | nil,
            prev_close: float() | nil
          }
  end

  defmodule TimesaleEvent do
    @moduledoc "Parsed timesale event from streaming API"
    defstruct [:symbol, :exchange, :bid, :ask, :last, :size, :date]

    @type t :: %__MODULE__{
            symbol: String.t(),
            exchange: String.t() | nil,
            bid: float() | nil,
            ask: float() | nil,
            last: float() | nil,
            size: integer() | nil,
            date: integer() | nil
          }
  end

  defmodule Session do
    @moduledoc "Represents a streaming session with timestamp tracking"
    defstruct [:session_id, :url, :created_at]

    @type t :: %__MODULE__{
            session_id: String.t(),
            url: String.t(),
            created_at: DateTime.t()
          }
  end

  @doc """
  Create a streaming market data session.
  """
  def create_market_session(client, params \\ %{}) do
    params =
      case params[:symbols] do
        symbols when is_list(symbols) ->
          Map.put(params, :symbols, Enum.join(symbols, ","))

        _ ->
          params
      end

    params =
      case params[:filter] do
        filter when is_list(filter) ->
          Map.put(params, :filter, Enum.join(filter, ","))

        _ ->
          params
      end

    form_params = Enum.map(params, fn {k, v} -> {to_string(k), to_string(v)} end)

    Req.post(client, url: "/markets/events/session", form: form_params)
    |> Client.handle_response()
  end

  @doc """
  Create a streaming account events session.

  Note: The account_id parameter is kept for API compatibility but is not used
  in the request path.
  """
  def create_account_session(client, _account_id) do
    Req.post(client, url: "/accounts/events/session", form: [])
    |> Client.handle_response()
  end

  @doc """
  Creates a Session struct from API response with timestamp.
  """
  def create_session_from_response(%{"stream" => %{"sessionid" => session_id, "url" => url}}) do
    {:ok,
     %Session{
       session_id: session_id,
       url: url,
       created_at: DateTime.utc_now()
     }}
  end

  def create_session_from_response(_), do: {:error, :invalid_response}

  @doc """
  Parses streaming event messages.
  """
  def parse_event(message) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses a raw JSON message into a typed event struct.
  """
  def parse_typed_event(message) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, data} -> parse_typed_event_from_map(data)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses a map (already decoded JSON) into a typed event struct.
  """
  def parse_typed_event_from_map(%{"type" => "quote"} = data) do
    {:ok, parse_quote_event(data)}
  end

  def parse_typed_event_from_map(%{"type" => "trade"} = data) do
    {:ok, parse_trade_event(data)}
  end

  def parse_typed_event_from_map(%{"type" => "summary"} = data) do
    {:ok, parse_summary_event(data)}
  end

  def parse_typed_event_from_map(%{"type" => "timesale"} = data) do
    {:ok, parse_timesale_event(data)}
  end

  def parse_typed_event_from_map(%{"type" => type}) do
    {:error, {:unknown_event_type, type}}
  end

  def parse_typed_event_from_map(_) do
    {:error, :missing_type}
  end

  @doc """
  Parses a quote event from a decoded JSON map.
  """
  def parse_quote_event(data) when is_map(data) do
    %QuoteEvent{
      symbol: data["symbol"],
      bid: parse_float(data["bid"]),
      bid_size: parse_int(data["bidsz"]),
      bid_exchange: data["bidexch"],
      bid_date: parse_int(data["biddate"]),
      ask: parse_float(data["ask"]),
      ask_size: parse_int(data["asksz"]),
      ask_exchange: data["askexch"],
      ask_date: parse_int(data["askdate"])
    }
  end

  @doc """
  Parses a trade event from a decoded JSON map.
  """
  def parse_trade_event(data) when is_map(data) do
    %TradeEvent{
      symbol: data["symbol"],
      price: parse_float(data["price"]),
      size: parse_int(data["size"]),
      exchange: data["exch"],
      cvol: parse_int(data["cvol"]),
      date: parse_int(data["date"]),
      last: parse_float(data["last"])
    }
  end

  @doc """
  Parses a summary event from a decoded JSON map.
  """
  def parse_summary_event(data) when is_map(data) do
    %SummaryEvent{
      symbol: data["symbol"],
      open: parse_float(data["open"]),
      high: parse_float(data["high"]),
      low: parse_float(data["low"]),
      prev_close: parse_float(data["prevClose"])
    }
  end

  @doc """
  Parses a timesale event from a decoded JSON map.
  """
  def parse_timesale_event(data) when is_map(data) do
    %TimesaleEvent{
      symbol: data["symbol"],
      exchange: data["exch"],
      bid: parse_float(data["bid"]),
      ask: parse_float(data["ask"]),
      last: parse_float(data["last"]),
      size: parse_int(data["size"]),
      date: parse_int(data["date"])
    }
  end

  defp parse_float(nil), do: nil
  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value / 1

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> nil
    end
  end

  defp parse_float(_), do: nil

  defp parse_int(nil), do: nil
  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_int(_), do: nil

  @doc """
  Builds WebSocket URL with session ID.

  ## Parameters

    - `session_id` - The streaming session ID
    - `type` - `:market` or `:account`
    - `sandbox_mode` - Whether to use sandbox WebSocket URL (default: false)
  """
  def build_websocket_url(session_id, type, sandbox_mode \\ false)

  def build_websocket_url(session_id, :market, sandbox_mode) do
    "#{websocket_base_url(sandbox_mode)}/markets/events?sessionid=#{session_id}"
  end

  def build_websocket_url(session_id, :account, sandbox_mode) do
    "#{websocket_base_url(sandbox_mode)}/accounts/events?sessionid=#{session_id}"
  end

  defp websocket_base_url(true = _sandbox), do: "wss://sandbox-ws.tradier.com/v1"
  defp websocket_base_url(false = _sandbox), do: "wss://ws.tradier.com/v1"

  @doc """
  Builds the subscription payload to send over WebSocket.
  """
  def build_subscription_payload(symbols, filters, session_id \\ nil) when is_list(symbols) do
    %{
      symbols: symbols,
      filter: filters,
      sessionid: session_id,
      linebreak: true
    }
  end

  @doc """
  Encodes a subscription payload to JSON for sending over WebSocket.
  """
  def encode_subscription_payload(symbols, filters, session_id \\ nil) do
    payload = build_subscription_payload(symbols, filters, session_id)
    Jason.encode(payload)
  end

  @doc """
  Checks if a session has expired based on creation time.
  """
  def session_expired?(%Session{created_at: created_at}) do
    now = DateTime.utc_now()
    diff_ms = DateTime.diff(now, created_at, :millisecond)
    diff_ms >= @session_expiry_ms
  end

  def session_expired?(_), do: true

  @doc """
  Calculates time until session expires in milliseconds.
  Returns 0 if already expired.
  """
  def time_until_expiry(%Session{created_at: created_at}) do
    now = DateTime.utc_now()
    age_ms = DateTime.diff(now, created_at, :millisecond)
    remaining = @session_expiry_ms - age_ms
    max(0, remaining)
  end

  def time_until_expiry(_), do: 0

  @doc """
  Returns session expiry time in milliseconds.
  """
  def session_expiry_ms, do: @session_expiry_ms

  @doc """
  Validates a streaming session by checking creation time.
  """
  def validate_session(%Session{} = session) do
    if session_expired?(session) do
      {:error, :expired}
    else
      {:ok, :valid}
    end
  end

  def validate_session(_), do: {:error, :invalid_session}

  @doc false
  def validate_session(_client, session_id) do
    {:ok, %{"session" => %{"id" => session_id, "active" => true}}}
  end
end
