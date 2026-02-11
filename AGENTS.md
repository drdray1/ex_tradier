# ExTradier — Agent Instructions

## Build & Test

```bash
MIX_ENV=test mix test          # Run all tests
MIX_ENV=test mix test --failed # Re-run failed tests
mix format                     # Format code
MIX_ENV=test mix credo         # Lint
```

Note: `MIX_ENV=test` is required if the shell has `MIX_ENV=dev` set globally.

## Architecture

Standalone Elixir library wrapping the Tradier brokerage API. Uses Req for HTTP, WebSockex for streaming.

### Module Structure

| Module | Role |
|--------|------|
| `ExTradier` | Public facade — `defdelegate` to domain modules |
| `ExTradier.Auth` | Req plugin — attaches Bearer token |
| `ExTradier.Client` | HTTP client factory (`new/2`), response handling |
| `ExTradier.User` | Account/profile endpoints |
| `ExTradier.MarketData` | Quotes, history, options, calendar |
| `ExTradier.Trading` | Order placement, modification, validation |
| `ExTradier.Watchlist` | Watchlist CRUD |
| `ExTradier.Streaming` | Event structs, session management, parsing |
| `ExTradier.Streaming.Client` | WebSockex wrapper |
| `ExTradier.Streaming.MarketConnection` | Market stream GenServer |
| `ExTradier.Streaming.AccountConnection` | Account stream GenServer |

### Key Patterns

- **Req plugin auth**: `ExTradier.Auth.attach/2` registers `:tradier_api_token` option and appends a request step
- **Client factory**: `Client.new/2` returns a `Req.Request` struct — pass `:plug` option for test mocking
- **Tagged tuples**: All API calls return `{:ok, data}` or `{:error, reason}`
- **Form encoding**: Tradier POST endpoints use form-encoded bodies (`Req.post(client, form: params)`)
- **Streaming**: Two-step — REST call creates session, then WebSocket connects with session ID

### Testing

- Fixtures: `test/support/fixtures.ex` (`ExTradier.Fixtures`)
- HTTP mocking: `Req.Test.expect/2` with unique stub names per test
- Test client: `Fixtures.test_client(StubName)` creates client with `plug: {Req.Test, StubName}`
- Streaming tests are pure function tests (no WebSocket connections)

### Code Style

- Standard Elixir formatting (98 char line width)
- Alphabetized aliases
- `snake_case` functions, predicates end with `?`
- Pattern match on response shapes, not status codes
