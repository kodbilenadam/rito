# Changelog

## 0.2.0 (2026-09-05)

- **Riot Sign On (RSO)**: new `Rito::RSO` module implementing the OAuth2
  authorization code flow against `auth.riotgames.com`:
  `authorization_url` (with generated CSRF state), `exchange_code`,
  `refresh`, `userinfo`, and `verify_id_token` (RS256 signature +
  iss/aud/exp validation via `/jwks.json`, with key-rotation-aware
  refetch). Token requests support `client_secret` basic, a static
  `client_assertion` (the RSO "100 year token"), or minted private-key
  JWT client assertions from an RSA `private_key`. Zero new runtime
  dependencies (stdlib `openssl`).

## 0.1.3 (2026-09-05)

- CI: publish via `rubygems/release-gem` so releases carry a Sigstore
  provenance attestation ("Built and signed on GitHub Actions"). No
  user-facing changes.

## 0.1.2 (2026-09-05)

- CI: release workflow uses valid `trusted-publisher` input and Node 24
  actions. No user-facing changes.

## 0.1.1 (2026-09-05)

- Forbidden (403) errors now hint that the API key may be expired
  (dev keys expire every 24h) instead of raising a bare message.

## 0.1.0 (2026-09-05)

Initial release.

- **HTTP layer**: Faraday 2.x with a per-host connection cache, JSON
  request/response middleware, and transport retries (5xx, connection
  failures) via faraday-retry.
- **Routing**: platform vs regional routing values with automatic escalation
  (`na1 → americas`), SEA→ASIA normalization for account-v1, and separate
  VALORANT platform sets (`na1, eu, ap, kr, latam, br`; console: `na, eu, ap`).
- **Rate limiting**: `AdaptiveLimiter` (default) learns limits from
  `X-App-Rate-Limit` / `X-Method-Rate-Limit` headers, syncs counters from
  `*-Count` headers, throttles pre-emptively, handles 429s by scope
  (application / method / service) honoring `Retry-After` with exponential
  backoff + jitter fallback. `NullLimiter` for reactive-only mode.
  `RedisLimiter` for multi-process deployments (soft dependency on `redis`).
- **Errors**: mapped hierarchy (400/401/403/404/405/415/429/5xx,
  ConnectionError/TimeoutError/SSLError); `RateLimited` carries
  `retry_after` and `limit_type`.
- **Models**: frozen `Data` classes with liberal mapping; unknown fields
  preserved in `.raw`.
- **Coverage**: account-v1; LoL summoner-v4, match-v5, champion-mastery-v4,
  champion-v3, league-v4, league-exp-v4, spectator-v5, lol-status-v4, clash-v1,
  lol-challenges-v1, tournament-v5 (+ stub); TFT summoner/league/match/status/
  spectator; VALORANT content/match/console-match/ranked/status; LoR
  match/ranked/status/deck/inventory (RSO); riftbound-content-v1.
- **Instrumentation**: `request.rito` ActiveSupport::Notifications events
  (no-op without ActiveSupport).
