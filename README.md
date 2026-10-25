# ExTradier

Elixir client for the [Tradier](https://tradier.com/) brokerage API.

Supports market data, trading (equity, options, multi-leg), account management, watchlists, OAuth, and real-time streaming via WebSocket or HTTP.

Built on [Req](https://hexdocs.pm/req), with `:telemetry` instrumentation and rate limit reporting.

## Installation

Add `ex_tradier` to your dependencies:

```elixir
def deps do
  [
    {:ex_tradier, git: "https://github.com/drdray1/ex_tradier.git", tag: "0.2.1"}
  ]
end
```

## Configuration

Configuration is optional — you can always pass a token straight to
`ExTradier.Client.new/2`. Configuring one lets you call `ExTradier.Client.new/0`.

```elixir
# config/runtime.exs (recommended, so secrets are read at boot rather than compile time)
config :ex_tradier,
  api_token: System.get_env("TRADIER_API_TOKEN"),
  sandbox: System.get_env("TRADIER_SANDBOX", "true") == "true"
```

`:sandbox` defaults to `true`, so you have to opt in to trading with real money.

## Quick Start

```elixir
# Create a client
client = ExTradier.Client.new("your_api_token")

# ...or from application config
client = ExTradier.Client.new()

# For sandbox/paper trading (the default)
client = ExTradier.Client.new("your_api_token", sandbox: true)

# Get a quote
{:ok, data} = ExTradier.get_quotes(client, "AAPL")

# ...with option greeks
{:ok, data} = ExTradier.get_quotes(client, "AAPL240119C00150000", greeks: true)

# Place a market order
{:ok, order} = ExTradier.place_order(client, "VA000001", %{
  class: "equity",
  symbol: "AAPL",
  side: "buy",
  quantity: 100,
  type: "market",
  duration: "day"
})

# Get account positions
{:ok, positions} = ExTradier.get_positions(client, "VA000001")
```

## API Coverage

### Market Data (`ExTradier.MarketData`)

- `get_quotes/3` — real-time quotes (`greeks`, `includeLotSize`)
- `post_quotes/3` — quotes for large symbol lists, sent in the request body
- `get_historical/3` — OHLCV history
- `get_timesales/3` — intraday tick data
- `get_option_chains/3` — option chains (`expiration`, `greeks`)
- `get_option_chains_with_greeks/3` — chains with greeks and IV inline
- `get_option_expirations/3` — expiration dates
- `get_option_strikes/4` — strike prices
- `lookup_option_symbols/3` — OCC symbols for an underlying
- `get_clock/2` — market clock
- `get_calendar/2` — market calendar
- `search_symbols/3` / `lookup_symbol/3` — symbol search and lookup
- `get_etb_list/1` — easy-to-borrow list

### Trading (`ExTradier.Trading`)

- `place_equity_order/3` — equity orders
- `place_option_order/3` — single-leg options
- `place_multileg_order/3` — multi-leg spreads
- `place_combo_order/3` — equity + option combos
- `place_oto_order/3` — one-triggers-other
- `place_oco_order/3` — one-cancels-other
- `place_otoco_order/3` — one-triggers-one-cancels-other
- `modify_order/4` / `cancel_order/3` — order management
- `get_orders/3` — paginated order list (`page`, `limit`, `status`, `includeTags`)
- `preview_order/3` — order cost preview
- `validate_order_params/1` — client-side validation

Multi-leg and combo orders are priced as a net amount, so their `type` is one of
`market`, `debit`, `credit` or `even` — `validate_multileg_order/1` enforces this
and requires a `price` for `debit`/`credit`.

### Account (`ExTradier.User`)

- `get_profile/1` — user profile
- `get_balances/2` — account balances
- `get_positions/2` — open positions
- `get_history/3` — account history
- `get_gainloss/3` — realized P&L

### Watchlists (`ExTradier.Watchlist`)

- CRUD operations for watchlists and symbols

### Position Groups (`ExTradier.Positions`)

- CRUD operations for account position groups

### OAuth (`ExTradier.OAuth`)

For applications acting on behalf of other Tradier users. A personal access
token is simpler if you only call the API as yourself.

```elixir
# 1. Redirect the user here, then verify the state you get back
url = ExTradier.OAuth.authorize_url(client_id, scope: [:read, :trade, :market], state: state)

# 2. Exchange the callback code for a 24 hour access token
{:ok, token} = ExTradier.OAuth.create_access_token(client_id, client_secret, code)
client = ExTradier.Client.new(token["access_token"], sandbox: false)

# 3. Approved partners can refresh without sending the user back
{:ok, token} = ExTradier.OAuth.refresh_access_token(client_id, client_secret, refresh_token)
```

### Streaming

- `ExTradier.Streaming` — event parsing and session management
- `ExTradier.Streaming.MarketConnection` — market data WebSocket
- `ExTradier.Streaming.AccountConnection` — account events WebSocket
- `ExTradier.Streaming.HttpConnection` — market data over HTTP streaming

Market events arrive as `QuoteEvent`, `TradeEvent`, `SummaryEvent`,
`TimesaleEvent` and `TradexEvent` structs; account events as `OrderEvent` and
`HeartbeatEvent`.

```elixir
# Start a market stream
{:ok, pid} = ExTradier.Streaming.MarketConnection.start_link(
  api_token: "your_token"
)

ExTradier.Streaming.MarketConnection.add_subscriber(pid, self())
ExTradier.Streaming.MarketConnection.subscribe(pid, ["AAPL", "MSFT"])

# Receive events
receive do
  {:stream_event, %ExTradier.Streaming.QuoteEvent{} = event} ->
    IO.inspect(event)
end
```

## Telemetry

Every request emits `[:ex_tradier, :request, :start | :stop | :exception]`.
`:stop` metadata carries the response status and the rate limit state parsed
from Tradier's `X-Ratelimit-*` headers, which is the cheapest way to keep an eye
on your quota (120 requests/minute in production for most endpoints, 60 for
trading).

```elixir
:telemetry.attach("tradier-rate-limit", [:ex_tradier, :request, :stop], fn
  _event, _measurements, %{rate_limit: %{available: available}}, _config when available < 10 ->
    Logger.warning("Tradier rate limit nearly exhausted: #{available} left")

  _event, _measurements, _metadata, _config ->
    :ok
end, nil)
```

Pass `telemetry: false` to `ExTradier.Client.new/2` to opt out.
See `ExTradier.Telemetry` for the full event reference.

## Tuning the HTTP client

```elixir
ExTradier.Client.new("token",
  max_retries: 5,          # default 3, on transient failures
  receive_timeout: 60_000, # default 30_000
  retry_log_level: false,  # silence Req's retry warnings
  req_options: [finch: [name: MyApp.Finch]]
)
```

Retries use capped, jittered exponential backoff (250ms–8s).

## Testing

Uses [Req.Test](https://hexdocs.pm/req/Req.Test.html) for HTTP mocking:

```elixir
# Create a test client with a plug stub
client = ExTradier.Client.new("test_token", plug: {Req.Test, MyTest.StubName})

# Set up expectations
Req.Test.expect(MyTest.StubName, fn conn ->
  Req.Test.json(conn, %{"quotes" => %{"quote" => %{"symbol" => "AAPL"}}})
end)
```

```bash
MIX_ENV=test mix test
```

## License

MIT — see [LICENSE](LICENSE).
