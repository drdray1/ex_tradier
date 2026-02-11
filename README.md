# ExTradier

Elixir client for the [Tradier](https://tradier.com/) brokerage API.

Supports market data, trading (equity, options, multi-leg), account management, watchlists, and real-time streaming via WebSocket.

## Installation

Add `ex_tradier` to your dependencies:

```elixir
def deps do
  [
    {:ex_tradier, git: "https://github.com/drdray1/ex_tradier.git", tag: "0.1.0"}
  ]
end
```

## Configuration

```elixir
# config/config.exs
config :ex_tradier,
  api_token: "your_api_token",
  sandbox: false

# config/runtime.exs (recommended for secrets)
config :ex_tradier,
  api_token: System.get_env("TRADIER_API_TOKEN"),
  sandbox: System.get_env("TRADIER_SANDBOX", "false") == "true"
```

## Quick Start

```elixir
# Create a client
client = ExTradier.Client.new("your_api_token")

# For sandbox/paper trading
client = ExTradier.Client.new("your_api_token", sandbox: true)

# Get a quote
{:ok, data} = ExTradier.get_quotes(client, "AAPL")

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

- `get_quotes/2` — real-time quotes
- `get_historical/3` — OHLCV history
- `get_timesales/3` — intraday tick data
- `get_option_chains/3` — option chains
- `get_option_expirations/2` — expiration dates
- `get_option_strikes/3` — strike prices
- `get_option_greeks/3` — Greeks data
- `get_clock/1` — market clock
- `get_calendar/2` — market calendar
- `search_symbols/2` — symbol search
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
- `preview_order/3` — order cost preview
- `validate_order_params/1` — client-side validation

### Account (`ExTradier.User`)

- `get_profile/1` — user profile
- `get_balances/2` — account balances
- `get_positions/2` — open positions
- `get_history/3` — account history
- `get_gainloss/3` — realized P&L

### Watchlists (`ExTradier.Watchlist`)

- CRUD operations for watchlists and symbols

### Streaming

- `ExTradier.Streaming` — event parsing and session management
- `ExTradier.Streaming.MarketConnection` — market data WebSocket
- `ExTradier.Streaming.AccountConnection` — account events WebSocket

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
