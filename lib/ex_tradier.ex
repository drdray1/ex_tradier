defmodule ExTradier do
  @moduledoc """
  Elixir client for the Tradier brokerage API.

  Provides a unified interface to all Tradier API modules including
  account management, market data, trading, watchlists, and real-time streaming.

  ## Quick Start

      # Create a client (sandbox mode by default)
      client = ExTradier.new("your_api_token")

      # Production mode
      client = ExTradier.new("your_api_token", sandbox: false)

      # User/Account operations
      {:ok, profile} = ExTradier.get_profile(client)
      {:ok, balances} = ExTradier.get_balances(client, account_id)

      # Market data
      {:ok, quote} = ExTradier.get_quote(client, "AAPL")
      {:ok, history} = ExTradier.get_historical(client, "AAPL", %{interval: "daily"})

      # Trading
      {:ok, order} = ExTradier.place_order(client, account_id, %{
        class: "equity", symbol: "AAPL", side: "buy",
        quantity: 100, type: "market", duration: "day"
      })

      # Streaming
      {:ok, pid} = ExTradier.start_market_stream(api_token: "your_token")
      ExTradier.stream_subscribe(pid, ["AAPL", "MSFT"])
  """

  alias ExTradier.{
    Client,
    MarketData,
    OAuth,
    Positions,
    Streaming,
    Trading,
    User,
    Watchlist
  }

  alias ExTradier.Streaming.{AccountConnection, HttpConnection, MarketConnection}

  # ========================================
  # Client
  # ========================================

  @doc """
  Creates a new Tradier API client with authentication token.

  ## Options

    - `:sandbox` - Use sandbox environment (default: true)
    - `:plug` - Test plug for `Req.Test` (default: nil)
  """
  defdelegate new(api_token, opts \\ []), to: Client

  @doc "Validates the API token."
  defdelegate validate_token(client), to: Client

  @doc "Verifies credentials and returns user profile."
  defdelegate verify_credentials(api_token, sandbox_mode \\ true), to: Client

  @doc "Performs a health check."
  defdelegate healthcheck(client), to: Client

  # ========================================
  # OAuth
  # ========================================

  @doc "Builds the OAuth authorization URL to redirect a user to."
  defdelegate authorize_url(client_id, opts \\ []), to: OAuth

  @doc "Exchanges an OAuth authorization code for an access token."
  defdelegate create_access_token(client_id, client_secret, code, opts \\ []), to: OAuth

  @doc "Exchanges an OAuth refresh token for a new access token."
  defdelegate refresh_access_token(client_id, client_secret, refresh_token, opts \\ []),
    to: OAuth

  # ========================================
  # User/Account API
  # ========================================

  @doc "Get user profile."
  defdelegate get_profile(client), to: User

  @doc "Get account balances."
  defdelegate get_balances(client, account_id), to: User

  @doc "Get historical balance data for an account."
  defdelegate get_historical_balances(client, account_id, params \\ %{}), to: User

  @doc "Get account positions."
  defdelegate get_positions(client, account_id), to: User

  @doc "Get account history."
  defdelegate get_history(client, account_id, params \\ %{}), to: User

  @doc "Get gain/loss information."
  defdelegate get_gainloss(client, account_id, params \\ %{}), to: User

  @doc "Get cost basis for a symbol."
  defdelegate get_cost_basis(client, account_id, symbol), to: User

  # ========================================
  # Market Data API
  # ========================================

  @doc """
  Get quote for a single symbol.
  """
  def get_quote(client, symbol, params \\ %{}) when is_binary(symbol) do
    MarketData.get_quotes(client, symbol, params)
  end

  @doc "Get quotes for one or more symbols."
  defdelegate get_quotes(client, symbols, params \\ %{}), to: MarketData

  @doc "Get historical pricing data."
  defdelegate get_historical(client, symbol, params \\ %{}), to: MarketData

  @doc "Get intraday time and sales data."
  defdelegate get_timesales(client, symbol, params \\ %{}), to: MarketData

  @doc "Get option chains."
  defdelegate get_option_chains(client, symbol, params \\ %{}), to: MarketData

  @doc "Get option strikes."
  defdelegate get_option_strikes(client, symbol, expiration, params \\ %{}), to: MarketData

  @doc "Get option expirations."
  defdelegate get_option_expirations(client, symbol, params \\ %{}), to: MarketData

  @doc "Lookup option symbols for an underlying."
  defdelegate lookup_option_symbols(client, symbol, params \\ %{}), to: MarketData

  @doc "Get real-time Greeks for an option chain."
  @doc deprecated: "Use get_option_chains_with_greeks/3 instead"
  defdelegate get_option_greeks(client, symbol, expiration, params \\ %{}), to: MarketData

  @doc "Get option chains with Greeks included."
  defdelegate get_option_chains_with_greeks(client, symbol, params \\ %{}), to: MarketData

  @doc "Get quotes via POST for large symbol lists."
  defdelegate post_quotes(client, symbols, params \\ %{}), to: MarketData

  @doc "Search for securities by company name."
  defdelegate search_symbols(client, query, params \\ %{}), to: MarketData

  @doc "Lookup symbol information."
  defdelegate lookup_symbol(client, symbol, params \\ %{}), to: MarketData

  @doc "Get market calendar."
  defdelegate get_calendar(client, params \\ %{}), to: MarketData

  @doc "Get market clock."
  defdelegate get_clock(client, params \\ %{}), to: MarketData

  @doc "Get ETB (Easy to Borrow) list."
  defdelegate get_etb_list(client), to: MarketData

  # ========================================
  # Trading API
  # ========================================

  @doc """
  Place an order. The order type is determined by the `class` field.
  Defaults to equity if class not specified.
  """
  def place_order(client, account_id, %{class: "equity"} = params) do
    Trading.place_equity_order(client, account_id, params)
  end

  def place_order(client, account_id, %{class: "option"} = params) do
    Trading.place_option_order(client, account_id, params)
  end

  def place_order(client, account_id, %{class: "multileg"} = params) do
    Trading.place_multileg_order(client, account_id, params)
  end

  def place_order(client, account_id, %{class: "combo"} = params) do
    Trading.place_combo_order(client, account_id, params)
  end

  def place_order(client, account_id, params) do
    params = Map.put_new(params, :class, "equity")
    place_order(client, account_id, params)
  end

  @doc "Preview an order before placing it."
  defdelegate preview_order(client, account_id, params), to: Trading

  @doc "Place OTO (One-Triggers-Other) order."
  defdelegate place_oto_order(client, account_id, params), to: Trading

  @doc "Place OCO (One-Cancels-Other) order."
  defdelegate place_oco_order(client, account_id, params), to: Trading

  @doc "Place OTOCO (One-Triggers-OCO) order."
  defdelegate place_otoco_order(client, account_id, params), to: Trading

  @doc "Modify an order."
  defdelegate modify_order(client, account_id, order_id, params), to: Trading

  @doc "Cancel an order."
  defdelegate cancel_order(client, account_id, order_id), to: Trading

  @doc "Get list of orders."
  defdelegate get_orders(client, account_id, params \\ %{}), to: Trading

  @doc "Get a specific order."
  defdelegate get_order(client, account_id, order_id, params \\ %{}), to: Trading

  # ========================================
  # Streaming API
  # ========================================

  @doc "Create a market data streaming session."
  def create_market_stream(client, symbols, filters \\ ["quote", "trade"]) do
    Streaming.create_market_session(client, %{symbols: symbols, filter: filters})
  end

  @doc "Create an account events streaming session."
  defdelegate create_account_stream(client, account_id),
    to: Streaming,
    as: :create_account_session

  @doc "Parse streaming event message."
  defdelegate parse_stream_event(message), to: Streaming, as: :parse_event

  @doc "Build WebSocket URL with session ID."
  defdelegate build_stream_url(session_id, type), to: Streaming, as: :build_websocket_url

  @doc "Parse a typed market streaming event."
  defdelegate parse_typed_event(message), to: Streaming

  @doc "Parse a typed account streaming event."
  defdelegate parse_account_event(message), to: Streaming

  # ========================================
  # Streaming Connection Management
  # ========================================

  @doc "Starts a managed market data streaming connection."
  defdelegate start_market_stream(opts), to: MarketConnection, as: :start_link

  @doc "Starts a managed account events streaming connection."
  defdelegate start_account_stream(opts), to: AccountConnection, as: :start_link

  @doc "Starts a managed HTTP streaming connection (alternative to WebSocket)."
  defdelegate start_http_market_stream(opts), to: HttpConnection, as: :start_link

  @doc "Subscribes to symbols on a market stream connection."
  defdelegate stream_subscribe(server, symbols), to: MarketConnection, as: :subscribe

  @doc "Unsubscribes from symbols on a market stream connection."
  defdelegate stream_unsubscribe(server, symbols), to: MarketConnection, as: :unsubscribe

  @doc "Registers a process to receive streaming events."
  def stream_add_subscriber(server, pid) do
    GenServer.cast(server, {:add_subscriber, pid})
  end

  @doc "Unregisters a process from receiving streaming events."
  def stream_remove_subscriber(server, pid) do
    GenServer.cast(server, {:remove_subscriber, pid})
  end

  @doc "Gets the status of a streaming connection."
  def stream_status(server) do
    GenServer.call(server, :get_status)
  end

  @doc "Gets detailed info about a streaming connection."
  def stream_info(server) do
    GenServer.call(server, :get_info)
  end

  @doc "Forces a reconnection of a streaming connection."
  def stream_reconnect(server) do
    GenServer.cast(server, :reconnect)
  end

  @doc "Stops a streaming connection."
  def stream_stop(server) do
    GenServer.stop(server, :normal)
  end

  # ========================================
  # Trading Validation
  # ========================================

  @doc "Validates order parameters before submission."
  defdelegate validate_order(params), to: Trading, as: :validate_order_params

  @doc "Validates equity order parameters."
  defdelegate validate_equity_order(params), to: Trading

  @doc "Validates option order parameters."
  defdelegate validate_option_order(params), to: Trading

  @doc "Validates multi-leg order parameters."
  defdelegate validate_multileg_order(params), to: Trading

  @doc "Validates OCO (One-Cancels-Other) order parameters."
  defdelegate validate_oco_order(params), to: Trading

  @doc "Validates OTOCO (One-Triggers-OCO) order parameters."
  defdelegate validate_otoco_order(params), to: Trading

  @doc "Returns list of valid equity order sides."
  defdelegate valid_equity_sides(), to: Trading

  @doc "Returns list of valid option order sides."
  defdelegate valid_option_sides(), to: Trading

  @doc "Returns list of valid single-leg order types."
  defdelegate valid_order_types(), to: Trading

  @doc "Returns list of valid multi-leg and combo order types."
  defdelegate valid_multileg_types(), to: Trading

  @doc "Returns list of valid order durations."
  defdelegate valid_durations(), to: Trading

  # ========================================
  # Position Groups API
  # ========================================

  @doc "Get all position groups for an account."
  defdelegate get_position_groups(client, account_id), to: Positions

  @doc "Create a position group."
  defdelegate create_position_group(client, account_id, params), to: Positions

  @doc "Update a position group."
  defdelegate update_position_group(client, account_id, group_id, params), to: Positions

  @doc "Delete a position group."
  defdelegate delete_position_group(client, account_id, group_id), to: Positions

  # ========================================
  # Watchlist API
  # ========================================

  @doc "Get all watchlists."
  defdelegate get_watchlists(client), to: Watchlist

  @doc "Get a specific watchlist."
  defdelegate get_watchlist(client, watchlist_id), to: Watchlist

  @doc "Create a watchlist."
  defdelegate create_watchlist(client, params), to: Watchlist

  @doc "Update a watchlist."
  defdelegate update_watchlist(client, watchlist_id, params), to: Watchlist

  @doc "Delete a watchlist."
  defdelegate delete_watchlist(client, watchlist_id), to: Watchlist

  @doc "Add symbols to a watchlist."
  defdelegate add_watchlist_symbols(client, watchlist_id, symbols),
    to: Watchlist,
    as: :add_symbols

  @doc "Remove a symbol from a watchlist."
  defdelegate remove_watchlist_symbol(client, watchlist_id, symbol),
    to: Watchlist,
    as: :remove_symbol

  # ========================================
  # Helper Functions
  # ========================================

  @doc """
  Extracts account ID from user profile.
  """
  def extract_account_id(%{"profile" => %{"account" => %{"account_number" => account_id}}}) do
    account_id
  end

  def extract_account_id(%{"profile" => %{"account" => accounts}}) when is_list(accounts) do
    case List.first(accounts) do
      %{"account_number" => account_id} -> account_id
      _ -> nil
    end
  end

  def extract_account_id(_), do: nil

  @doc """
  Normalizes a quote response to a consistent format.
  """
  def normalize_quote(%{"quotes" => %{"quote" => quote}}) when is_map(quote) do
    quote
  end

  def normalize_quote(%{"quotes" => %{"quote" => quotes}}) when is_list(quotes) do
    quotes
  end

  def normalize_quote(data), do: data

  @doc """
  Normalizes positions response to a list.
  """
  def normalize_positions(%{"positions" => %{"position" => positions}})
      when is_list(positions) do
    positions
  end

  def normalize_positions(%{"positions" => %{"position" => position}})
      when is_map(position) do
    [position]
  end

  def normalize_positions(%{"positions" => "null"}), do: []
  def normalize_positions(_), do: []
end
