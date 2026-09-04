# AGENTS.md

Guide for AI agents working on `rito`, a Ruby client for the Riot Games API.
Read this before changing anything under `lib/` or `test/`.

## Verify

Every change ends with both green, in this order:

```
bundle exec rake lint
bundle exec rake test
```

Completion criterion: rubocop reports no offenses and the full suite passes
(82+ runs, 0 failures). If you touched a limiter, also run the Redis-backed
tests against a real Redis (`REDIS_URL`, defaults to `redis://127.0.0.1:6379`);
they skip silently when no Redis is reachable.

## Conventions (do not rediscover these)

- **Kane-style gem.** Class accessors for config, Minitest (never RSpec),
  explicit code (no `method_missing`), minimal runtime dependencies
  (Faraday is the only one). The `andrew-kane-gem-writer` skill is installed
  at `.agents/skills/andrew-kane-gem-writer/` — consult it when unsure about style.
- **No comments** unless explaining a non-obvious invariant (e.g. the 5xx
  ordering rule below).
- **Version** lives only in `lib/rito/version.rb`; `rito.gemspec` reads it.
  Every user-visible change gets a `CHANGELOG.md` entry.

## Testing

- Tests are Minitest + WebMock (`WebMock.disable_net_connect!` in
  `test/test_helper.rb`). Stubs must use full URLs with `https://` and the
  exact encoded path; bare-host stubs silently match nothing.
- Stubs returning JSON bodies must set `Content-Type: application/json`,
  or the response JSON middleware skips parsing and the body stays a string.
- VCR cassettes in `test/vcr_cassettes/` hold real recorded responses with
  API keys filtered. Re-record with `bundle exec rake cassettes` (needs
  `RIOT_API_KEY_TEST` in `.env`). Grep the cassettes for `RGAPI` after
  recording; a leaked key is a release blocker.
- API keys live only in `.env` (gitignored). No key may appear in any
  committed file, log line, or error message.

## Adding an endpoint

1. New file under `lib/rito/endpoints/<product>/`, class inherits
   `Endpoints::Base`, declares `ROUTING` — one of `:platform`, `:regional`,
   `:valorant_platform`, `:valorant_console_platform`.
2. Methods are noun-first, keyword-only args, `region: nil` last. Escape
   every path segment with the inherited `escape`.
3. Register in `lib/rito.rb` require list.
4. Add a client accessor if it's a new game/gateway (see `Rito::Tft::Api`
   for the module + gateway-class pattern; gateway classes live outside
   `Endpoints` to avoid module/class name collisions).
5. Add a Minitest file stubbing the exact URL(s); assert host routing,
   payload mapping, and `.raw` preservation.
6. Update the coverage table in `README.md` and `CHANGELOG.md`.

## Non-obvious invariants (the codebase will not confess these)

- **RSO token requests are never retried.** `Rito::RSO::Client` uses its own
  bare Faraday connection (no faraday-retry, no rate-limit middleware):
  authorization codes and refresh tokens are one-time, so a replayed POST
  `/token` can burn the grant. RSO failures raise `Rito::RSO::OAuthError`
  (carries `error_code`/`error_description`), not the API 4xx hierarchy.

- **5xx must not raise inside response middleware.** `RiotErrors` skips 5xx;
  `faraday-retry` (registered above it) retries internally, and the final
  `ServerError`/`ServiceUnavailable` is raised in `Client#request` after
  retries exhaust. Raising earlier aborts the retry loop after one attempt.
- **Response-phase order is reverse of registration.** `RateLimitObserve`
  is registered last so it syncs limiter state before `RiotErrors` raises —
  the 429 block must be in place before any retry loop runs.
- **Region and bucket are derived from `env.url`** (host prefix, first two
  path segments) because Faraday 2.x gives middleware a fresh `Env` per
  request; custom per-request data does not flow through.
- **Rate-limit headers are `limit:window_seconds` pairs** (`"20:1,100:120"`).
  Limits are learned from headers, never hard-coded. Missing `Retry-After`
  on a 429 is a real Riot behavior (see RIOT-API-NOTES.md §1.3) — backoff
  must tolerate it.
- **Models are frozen `Data` classes with liberal `from_api`**; unknown
  fields go into `.raw`. Riot changes payloads without notice (live
  example: `champion-rotations` swapped to `{"sr": [...], "newplayer": [...]}`
  mid-development). Map only current, observed shapes.
- **`account-v1` has no SEA host** (`sea` normalizes to `asia`); regional
  endpoints auto-escalate platform values (`na1 → americas`).

## Deep dives

- `RIOT-API-NOTES.md` — Riot API research the gem encodes: routing
  tables, rate-limit grammar, error semantics.
- `README.md` — public API examples; keep it in sync with any accessor change.
