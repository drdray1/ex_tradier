defmodule ExTradier.MarketData do
  @moduledoc """
  Tradier Market Data API - Quotes, historical data, and market information.
  """

  alias ExTradier.Client

  @type params :: map() | keyword()

  @doc """
  Get quote(s) for one or more symbols.

  ## Options

    - `:greeks` - Include option greeks and implied volatility (default: `false`)
    - `:includeLotSize` - Include the security's lot size (default: `false`)

  ## Examples

      iex> get_quotes(client, "AAPL")
      {:ok, %{"quotes" => %{"quote" => %{"symbol" => "AAPL", ...}}}}

      iex> get_quotes(client, ["AAPL", "MSFT"])
      {:ok, %{"quotes" => %{"quote" => [%{...}, %{...}]}}}

      iex> get_quotes(client, "AAPL240119C00150000", greeks: true)
      {:ok, %{"quotes" => %{"quote" => %{"greeks" => %{"delta" => 0.55, ...}}}}}
  """
  @spec get_quotes(Client.client(), String.t() | [String.t()], params()) :: Client.response()
  def get_quotes(client, symbols, params \\ %{})

  def get_quotes(client, symbols, params) when is_list(symbols) do
    get_quotes(client, Enum.join(symbols, ","), params)
  end

  def get_quotes(client, symbol, params) when is_binary(symbol) do
    Req.get(client, url: "/markets/quotes", params: Client.to_params(params, symbols: symbol))
    |> Client.handle_response()
  end

  @doc """
  Get quotes via POST for large symbol lists (100+).

  Symbols are sent in a form-encoded request body rather than the query string,
  so this endpoint is not subject to URL length limits.

  Accepts the same options as `get_quotes/3`.
  """
  @spec post_quotes(Client.client(), String.t() | [String.t()], params()) :: Client.response()
  def post_quotes(client, symbols, params \\ %{})

  def post_quotes(client, symbols, params) when is_list(symbols) do
    post_quotes(client, Enum.join(symbols, ","), params)
  end

  def post_quotes(client, symbols, params) when is_binary(symbols) do
    Req.post(client,
      url: "/markets/quotes",
      form: Client.to_form(params, symbols: symbols)
    )
    |> Client.handle_response()
  end

  @doc """
  Get historical pricing (OHLCV bars).

  ## Options

    - `:interval` - `"daily"` (default), `"weekly"`, or `"monthly"`
    - `:start` / `:end` - `YYYY-MM-DD` bounds
    - `:session_filter` - `"all"` or `"open"` (default)

  ## Examples

      iex> get_historical(client, "AAPL", %{interval: "daily", start: "2024-01-01"})
      {:ok, %{"history" => %{"day" => [...]}}}
  """
  @spec get_historical(Client.client(), String.t(), params()) :: Client.response()
  def get_historical(client, symbol, params \\ %{}) do
    Req.get(client, url: "/markets/history", params: Client.to_params(params, symbol: symbol))
    |> Client.handle_response()
  end

  @doc """
  Get intraday time and sales data.

  ## Options

    - `:interval` - `"tick"`, `"1min"`, `"5min"`, or `"15min"`
    - `:start` / `:end` - `YYYY-MM-DD HH:MM` bounds
    - `:session_filter` - `"all"` or `"open"` (default)
  """
  @spec get_timesales(Client.client(), String.t(), params()) :: Client.response()
  def get_timesales(client, symbol, params \\ %{}) do
    Req.get(client,
      url: "/markets/timesales",
      params: Client.to_params(params, symbol: symbol)
    )
    |> Client.handle_response()
  end

  @doc """
  Get option chains for a symbol.

  ## Options

    - `:expiration` - `YYYY-MM-DD` expiration date (required by Tradier)
    - `:greeks` - Include greeks and implied volatility (default: `false`)
  """
  @spec get_option_chains(Client.client(), String.t(), params()) :: Client.response()
  def get_option_chains(client, symbol, params \\ %{}) do
    Req.get(client,
      url: "/markets/options/chains",
      params: Client.to_params(params, symbol: symbol)
    )
    |> Client.handle_response()
  end

  @doc """
  Get option strikes for a symbol and expiration.

  ## Options

    - `:includeAllRoots` - Include strikes from all option roots (default: `false`)
  """
  @spec get_option_strikes(Client.client(), String.t(), String.t(), params()) ::
          Client.response()
  def get_option_strikes(client, symbol, expiration, params \\ %{}) do
    Req.get(client,
      url: "/markets/options/strikes",
      params: Client.to_params(params, symbol: symbol, expiration: expiration)
    )
    |> Client.handle_response()
  end

  @doc """
  Get option expirations for a symbol.

  ## Options

    - `:includeAllRoots` - Include expirations from all option roots (default: `false`)
    - `:strikes` - Include the strike list for each expiration (default: `false`)
    - `:contractSize` - Include contract size (default: `false`)
    - `:expirationType` - Include expiration type, e.g. `"weeklys"` (default: `false`)
  """
  @spec get_option_expirations(Client.client(), String.t(), params()) :: Client.response()
  def get_option_expirations(client, symbol, params \\ %{}) do
    Req.get(client,
      url: "/markets/options/expirations",
      params: Client.to_params(params, symbol: symbol)
    )
    |> Client.handle_response()
  end

  @doc """
  Lookup option symbols for an underlying.
  """
  @spec lookup_option_symbols(Client.client(), String.t(), params()) :: Client.response()
  def lookup_option_symbols(client, symbol, params \\ %{}) do
    Req.get(client,
      url: "/markets/options/lookup",
      params: Client.to_params(params, underlying: symbol)
    )
    |> Client.handle_response()
  end

  @doc """
  Get real-time Greeks for an option chain.

  > #### Deprecated {: .warning}
  >
  > Tradier no longer documents a standalone `/markets/options/greeks` endpoint.
  > Use `get_option_chains_with_greeks/3` (or pass `greeks: true` to
  > `get_option_chains/3`), which returns greeks and IV inline on each contract.

  Powered by ORATS - may require separate entitlement.
  """
  @doc deprecated: "Use get_option_chains_with_greeks/3 instead"
  @spec get_option_greeks(Client.client(), String.t(), String.t(), params()) :: Client.response()
  def get_option_greeks(client, symbol, expiration, params \\ %{}) do
    Req.get(client,
      url: "/markets/options/greeks",
      params: Client.to_params(params, symbol: symbol, expiration: expiration)
    )
    |> Client.handle_response()
  end

  @doc """
  Get option chains with Greeks included.
  """
  @spec get_option_chains_with_greeks(Client.client(), String.t(), params()) :: Client.response()
  def get_option_chains_with_greeks(client, symbol, params \\ %{}) do
    get_option_chains(client, symbol, Client.to_params(params, greeks: true))
  end

  @doc """
  Search for securities by company name or description.

  ## Options

    - `:indexes` - Include market indexes in the results (default: `true`)
  """
  @spec search_symbols(Client.client(), String.t(), params()) :: Client.response()
  def search_symbols(client, query, params \\ %{}) do
    Req.get(client, url: "/markets/search", params: Client.to_params(params, q: query))
    |> Client.handle_response()
  end

  @doc """
  Lookup symbol information.

  ## Options

    - `:exchanges` - Comma-separated exchange codes to filter by, e.g. `"Q,N"`
    - `:types` - Comma-separated security types, e.g. `"stock,etf,index"`
  """
  @spec lookup_symbol(Client.client(), String.t(), params()) :: Client.response()
  def lookup_symbol(client, symbol, params \\ %{}) do
    Req.get(client, url: "/markets/lookup", params: Client.to_params(params, q: symbol))
    |> Client.handle_response()
  end

  @doc """
  Get current market calendar (trading days).

  ## Options

    - `:month` - Month number, `1`..`12` (defaults to the current month)
    - `:year` - Four digit year (defaults to the current year)
  """
  @spec get_calendar(Client.client(), params()) :: Client.response()
  def get_calendar(client, params \\ %{}) do
    Req.get(client, url: "/markets/calendar", params: Client.to_params(params))
    |> Client.handle_response()
  end

  @doc """
  Get market clock (open/close times and status).

  ## Options

    - `:delayed` - Return the delayed-data clock state (default: `false`)
  """
  @spec get_clock(Client.client(), params()) :: Client.response()
  def get_clock(client, params \\ %{}) do
    Req.get(client, url: "/markets/clock", params: Client.to_params(params))
    |> Client.handle_response()
  end

  @doc """
  Get ETB (Easy to Borrow) securities list for short selling.
  """
  @spec get_etb_list(Client.client()) :: Client.response()
  def get_etb_list(client) do
    Req.get(client, url: "/markets/etb")
    |> Client.handle_response()
  end
end
