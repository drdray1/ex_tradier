# ExTradier — Agent Instructions

## Build & Test

```bash
MIX_ENV=test mix test           # Run all tests
MIX_ENV=test mix test --failed  # Re-run failed tests
mix format                      # Format code
MIX_ENV=test mix credo --strict # Lint (should report zero issues)
MIX_ENV=test mix hex.audit      # Check deps for security advisories
```

Note: `MIX_ENV=test` is required if the shell has `MIX_ENV=dev` set globally.

## Architecture

Standalone Elixir library wrapping the Tradier brokerage API. Uses Req for HTTP, WebSockex for streaming.

### Module Structure

| Module | Role |
|--------|------|
| `ExTradier` | Public facade — `defdelegate` to domain modules |
| `ExTradier.Auth` | Req plugin — attaches Bearer token |
| `ExTradier.OAuth` | OAuth 2.0 authorization code flow |
| `ExTradier.Client` | HTTP client factory (`new/0,2`), param helpers, response handling |
| `ExTradier.Telemetry` | Req plugin — emits `[:ex_tradier, :request, _]` events |
| `ExTradier.User` | Account/profile endpoints |
| `ExTradier.MarketData` | Quotes, history, options, calendar |
| `ExTradier.Trading` | Order placement, modification, validation |
| `ExTradier.Watchlist` | Watchlist CRUD |
| `ExTradier.Positions` | Position group CRUD |
| `ExTradier.Streaming` | Event structs, session management, parsing |
| `ExTradier.Streaming.Client` | WebSockex wrapper |
| `ExTradier.Streaming.MarketConnection` | Market stream GenServer |
| `ExTradier.Streaming.AccountConnection` | Account stream GenServer |
| `ExTradier.Streaming.HttpConnection` | HTTP streaming GenServer |

### Key Patterns

- **Req plugin auth**: `ExTradier.Auth.attach/2` registers `:tradier_api_token` option and appends a request step
- **Client factory**: `Client.new/2` returns a `Req.Request` struct — pass `:plug` option for test mocking, `:req_options` as an escape hatch
- **Tagged tuples**: All API calls return `{:ok, data}` or `{:error, reason}`
- **Param helpers**: `Client.to_params/2` and `Client.to_form/2` normalize maps or keyword lists, drop `nil`s, and let the caller's params be overridden by values the function controls. Use these rather than hand-rolling `Enum.map(&to_string/1)`.
- **Form encoding**: Tradier POST endpoints use form-encoded bodies (`Req.post(client, form: params)`). Note `post_quotes/3` must send symbols in the **body**, not the query string — that is the whole point of the endpoint.
- **Streaming**: Two-step — REST call creates session, then WebSocket connects with session ID
- **Telemetry**: attached by default in `Client.new/2`; disable per client with `telemetry: false`

### Testing

- Fixtures: `test/support/fixtures.ex` (`ExTradier.Fixtures`)
- HTTP mocking: `Req.Test.expect/2` with unique stub names per test
- Test client: `Fixtures.test_client(StubName)` creates client with `plug: {Req.Test, StubName}`
- Streaming tests are pure function tests (no WebSocket connections)
- Tests that touch global state must be `async: false`: `telemetry_test.exs` (handlers are global) and `client_config_test.exs` (application env)
- Plug decodes Tradier's indexed form fields (`option_symbol[0]`) into nested maps, so assert on `%{"0" => ...}` rather than the literal key

### Code Style

- Standard Elixir formatting (98 char line width)
- Alphabetized aliases (credo's `AliasOrder` check is enforced)
- `snake_case` functions, predicates end with `?`
- Pattern match on response shapes, not status codes
