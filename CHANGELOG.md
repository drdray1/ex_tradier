# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0]

### Added

- `ExTradier.OAuth` — the OAuth 2.0 authorization code flow (`authorize_url/2`,
  `create_access_token/4`, `refresh_access_token/4`, `scopes/0`, `expires_at/2`),
  so an application can act on behalf of other Tradier users instead of only
  using a personal access token. Also exposed on the `ExTradier` facade.
- `ExTradier.Telemetry` — `[:ex_tradier, :request, :start | :stop | :exception]`
  events, attached by default. `:stop` metadata carries the response status and
  the parsed rate limit state. Opt out with `ExTradier.Client.new(token,
  telemetry: false)`.
- `ExTradier.Client.new/2` options: `:retry`, `:max_retries`, `:retry_log_level`,
  `:receive_timeout`, `:telemetry`, and `:req_options` as an escape hatch for
  anything not exposed directly (custom Finch pool, connect options, and so on).
- Every request now sends a `user-agent` identifying the library and Elixir
  version (`ExTradier.Client.user_agent/0`).
- `ExTradier.Client.to_params/2` and `to_form/2` — shared param normalization
  that accepts maps or keyword lists, drops `nil` values, and prevents a
  caller-supplied param from overriding a value the function must control (a
  `symbols` param can no longer contradict the symbol argument).
- Documented Tradier request params that previously had no way to be passed:
  - quotes: `greeks`, `includeLotSize` (`get_quotes/3`, `post_quotes/3`)
  - options: `includeAllRoots`, `strikes`, `contractSize`, `expirationType`
  - search/lookup: `indexes`, `exchanges`, `types`
  - clock: `delayed`; orders: `page`, `limit`, `status`, `includeTags`
    (`get_orders/3` and now `get_order/4`)
- `ExTradier.Streaming.TimesaleEvent` gained the `seq`, `flag`, `cancel`,
  `correction` and `session` fields Tradier sends. `cancel`/`correction` matter
  for anything computing volume or VWAP from the stream.
- Typed account stream events: `ExTradier.Streaming.OrderEvent` and
  `HeartbeatEvent`, with `parse_account_event/1` and
  `parse_account_event_from_map/1`. ISO 8601 timestamps are parsed to
  `DateTime`. `ExTradier.Streaming.AccountConnection` now broadcasts these
  structs; unrecognized event types still arrive as the decoded map.
- `ExTradier.Trading.valid_multileg_types/0`.
- `@spec` annotations across the public API of every module.

### Changed

- **Bumped `req` from `~> 0.5` to `~> 0.7`.** This clears security advisories in
  the transitive dependency tree (`mint`, `hpax`, `finch`) and picks up Req 0.6's
  opt-in decompression, which closes a decompression-bomb vector. `mix hex.audit`
  is now clean.
- Development dependencies: `credo` `1.7.16` → `1.7.19` (1.7.16 crashed on Elixir
  1.20's sigil tokens, so the project could not be linted at all), `mimic`
  `~> 1.7` → `~> 2.3`, `ex_doc` to `0.40.3`. `mix credo --strict` now reports zero
  issues; the alias ordering the project documents is actually enforced.
- **Dropped the `decimal` dependency.** It was declared but never used anywhere in
  the library, and the locked version carried its own advisory.
- Retry backoff is now capped at 8s and jittered across the top half of each
  window, instead of doubling without limit in lockstep across clients. Req's
  retry logging is emitted at `:warning` and can be disabled.
- `ExTradier.Client.extract_rate_limit/1` now parses `X-Ratelimit-Allowed` (a
  documented header it previously ignored) and returns the fields that *are*
  present instead of `nil` whenever any one header was missing. The returned map
  gained an `:allowed` key. `:expiry` is documented as milliseconds, matching
  Tradier.
- `ExTradier.Trading.validate_multileg_order/1` now validates `:type` against
  `market`/`debit`/`credit`/`even` — the net-priced types Tradier documents for
  multi-leg orders — and requires `:price` for `debit`/`credit`. It previously
  applied the single-leg `market`/`limit`/`stop`/`stop_limit` rules, which
  rejected valid spread orders and accepted invalid ones.
- Order, watchlist, position group and streaming session params accept keyword
  lists as well as maps, and `nil` values are dropped rather than sent as empty
  strings.

### Fixed

- `ExTradier.MarketData.post_quotes/3` sent symbols as **query parameters**
  rather than a form body, so it hit the same URL length limit as the GET
  endpoint it exists to work around. Symbols are now sent in the request body.
- `ExTradier.Streaming.MarketConnection` and `HttpConnection` used
  `map_size(subscribed_symbols) == 0` to guard against connecting with no
  symbols. `subscribed_symbols` is a `MapSet`, and `map_size(MapSet.new())` is
  `2` (the struct's own keys), so the guard never fired and subscribing to an
  empty list opened a session with nothing subscribed. Now uses `MapSet.size/1`.
- `ExTradier.Trading.place_multileg_order/3` raised a `FunctionClauseError` when
  given params that already used Tradier's indexed `option_symbol[0]` keys
  instead of a `:legs` list.

### Removed

- The two-argument `validate_session` on `ExTradier.Streaming`, a stub that
  ignored its arguments and always returned
  `{:ok, %{"session" => %{"active" => true}}}`. Tradier exposes no endpoint for
  querying session state; use `ExTradier.Streaming.validate_session/1`, which
  performs the real local expiry check.

### Deprecated

- `ExTradier.MarketData.get_option_greeks/4` (and the `ExTradier` facade
  delegate). Tradier no longer documents a standalone `/markets/options/greeks`
  endpoint. Use `get_option_chains_with_greeks/3`, or pass `greeks: true` to
  `get_option_chains/3`, which returns greeks and IV inline on each contract.

## [0.1.2]

- Allow `decimal ~> 3.0`.

## [0.1.1]

- Fix retry delay crash on the first retry attempt.

## [0.1.0]

- Initial release.
