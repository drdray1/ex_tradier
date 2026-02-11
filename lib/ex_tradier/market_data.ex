defmodule ExTradier.MarketData do
  @moduledoc """
  Tradier Market Data API - Quotes, historical data, and market information.
  """

  alias ExTradier.Client

  @doc """
  Get quote(s) for one or more symbols.

  ## Examples

      iex> get_quotes(client, "AAPL")
      {:ok, %{"quotes" => %{"quote" => %{"symbol" => "AAPL", ...}}}}

      iex> get_quotes(client, ["AAPL", "MSFT"])
      {:ok, %{"quotes" => %{"quote" => [%{...}, %{...}]}}}
  """
  def get_quotes(client, symbols) when is_list(symbols) do
    symbols_param = Enum.join(symbols, ",")
    get_quotes(client, symbols_param)
  end

  def get_quotes(client, symbol) when is_binary(symbol) do
    Req.get(client, url: "/markets/quotes", params: [symbols: symbol])
    |> Client.handle_response()
  end

  @doc """
  Get quotes via POST for large symbol lists (100+).
  Better performance than GET for bulk requests due to no URL length limits.
  """
  def post_quotes(client, symbols) when is_list(symbols) do
    symbols_param = Enum.join(symbols, ",")
    post_quotes(client, symbols_param)
  end

  def post_quotes(client, symbols) when is_binary(symbols) do
    Req.post(client, url: "/markets/quotes", params: [symbols: symbols])
    |> Client.handle_response()
  end

  @doc """
  Get historical pricing (OHLCV bars).

  ## Examples

      iex> get_historical(client, "AAPL", %{interval: "daily", start: "2024-01-01"})
      {:ok, %{"history" => %{"day" => [...]}}}
  """
  def get_historical(client, symbol, params \\ %{}) do
    params = Map.put(params, :symbol, symbol)

    Req.get(client, url: "/markets/history", params: Map.to_list(params))
    |> Client.handle_response()
  end

  @doc """
  Get intraday time and sales data.
  """
  def get_timesales(client, symbol, params \\ %{}) do
    params = Map.put(params, :symbol, symbol)

    Req.get(client, url: "/markets/timesales", params: Map.to_list(params))
    |> Client.handle_response()
  end

  @doc """
  Get option chains for a symbol.
  """
  def get_option_chains(client, symbol, params \\ %{}) do
    params = Map.put(params, :symbol, symbol)

    Req.get(client, url: "/markets/options/chains", params: Map.to_list(params))
    |> Client.handle_response()
  end

  @doc """
  Get option strikes for a symbol and expiration.
  """
  def get_option_strikes(client, symbol, expiration) do
    Req.get(client,
      url: "/markets/options/strikes",
      params: [symbol: symbol, expiration: expiration]
    )
    |> Client.handle_response()
  end

  @doc """
  Get option expirations for a symbol.
  """
  def get_option_expirations(client, symbol) do
    Req.get(client, url: "/markets/options/expirations", params: [symbol: symbol])
    |> Client.handle_response()
  end

  @doc """
  Lookup option symbols for an underlying.
  """
  def lookup_option_symbols(client, symbol, params \\ %{}) do
    params = Map.put(params, :underlying, symbol)

    Req.get(client, url: "/markets/options/lookup", params: Map.to_list(params))
    |> Client.handle_response()
  end

  @doc """
  Get real-time Greeks for an option chain.
  Powered by ORATS - may require separate entitlement.
  """
  def get_option_greeks(client, symbol, expiration, params \\ %{}) do
    params =
      params
      |> Map.put(:symbol, symbol)
      |> Map.put(:expiration, expiration)

    Req.get(client, url: "/markets/options/greeks", params: Map.to_list(params))
    |> Client.handle_response()
  end

  @doc """
  Get option chains with Greeks included.
  """
  def get_option_chains_with_greeks(client, symbol, params \\ %{}) do
    params = Map.put(params, :greeks, true)
    get_option_chains(client, symbol, params)
  end

  @doc """
  Search for symbols.
  """
  def search_symbols(client, query) do
    Req.get(client, url: "/markets/search", params: [q: query])
    |> Client.handle_response()
  end

  @doc """
  Lookup symbol information.
  """
  def lookup_symbol(client, symbol) do
    Req.get(client, url: "/markets/lookup", params: [q: symbol])
    |> Client.handle_response()
  end

  @doc """
  Get current market calendar (trading days).
  """
  def get_calendar(client, params \\ %{}) do
    Req.get(client, url: "/markets/calendar", params: Map.to_list(params))
    |> Client.handle_response()
  end

  @doc """
  Get market clock (open/close times and status).
  """
  def get_clock(client) do
    Req.get(client, url: "/markets/clock")
    |> Client.handle_response()
  end

  @doc """
  Get ETB (Easy to Borrow) securities list for short selling.
  """
  def get_etb_list(client) do
    Req.get(client, url: "/markets/etb")
    |> Client.handle_response()
  end
end
