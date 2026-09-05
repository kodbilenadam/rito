# Rito — Riot API notes

Research notes on the Riot Games API that the gem encodes. This is the
"why" behind the routing tables, the rate-limit strategy, and the error
hierarchy.

## 1.1 Routing values

Riot routes every request through two kinds of hosts. An endpoint is bound to one of the two — this is the single most common integration bug, so it becomes a first-class concept in the gem, not a string the user passes around.

**Platform routing values** (service topology, e.g. `na1.api.riotgames.com`):
`BR1, EUN1, EUW1, JP1, KR, LA1, LA2, ME1, NA1, OC1, PBE1, RU, SG2, TR1, TW2, VN2`
(PH2/TH2 no longer exist after Riot's SEA consolidation; PBE1 serves
lol-challenges-v1, lol-status-v4 and tft-status-v1.)

**Regional (cluster) routing values** (e.g. `americas.api.riotgames.com`):
`AMERICAS, ASIA, EUROPE, SEA`

Platform → regional cluster mapping (used for automatic escalation, e.g. resolving a summoner on `na1` then fetching matches on `americas`):

| Regional | Platforms |
| --- | --- |
| AMERICAS | NA1, BR1, LA1, LA2 |
| EUROPE | EUW1, EUN1, TR1, RU, ME1 |
| ASIA | KR, JP1 |
| SEA | OC1, SG2, TW2, VN2 |

Gotchas encoded into the gem:

- **account-v1** serves only `AMERICAS / EUROPE / ASIA` — there is no SEA host; `sea` accounts must be queried via `asia`. The routing table normalizes this.
- Some endpoints are pinned differently per game (e.g. `summoner-v4` is platform-routed; `match-v5` is regional-routed; VALORANT `val-match-v1` is platform-routed).
- Each endpoint module declares its routing kind (`:platform` or `:regional`) so the client resolves the correct host automatically and can escalate `na1 → americas` transparently.

## 1.2 Auth

- Production/personal keys: header `X-Riot-Token: <key>`.
- RSO / OAuth endpoints (`/accounts/me`, `lol-rso-match-v1`, `lor-deck-v1`): header `Authorization: Bearer <accessToken>`. The gem supports a key **or** a bearer token per client; `accounts/me`-style endpoints accept a per-call token override.

## 1.3 Rate limiting model

Three layers, all enforced **per key per region**:

1. **Application limit** — every call in a region counts against the key's app buckets (e.g. `20:1,100:120`).
2. **Method limit** — per endpoint (`/lol/summoner/v4/summoners/*`), own buckets (e.g. `2000:10`).
3. **Service limit** — the underlying game service may rate-limit independently. When it does, `X-Rate-Limit-Type` is **absent** from the 429.

Header grammar (all `value:window_seconds`, comma-separated):

```
X-App-Rate-Limit:        20:1,100:120
X-App-Rate-Limit-Count:  5:1,42:120
X-Method-Rate-Limit:     2000:10
X-Method-Rate-Limit-Count: 137:10
```

On `429 Too Many Requests`:

| Header | Meaning |
| --- | --- |
| `Retry-After` | Seconds to wait. **Not guaranteed** — Riot removed it temporarily in Feb 2025 (developer-relations#1050); the gem must tolerate its absence. |
| `X-Rate-Limit-Type` | `application`, `method`, or `service`. Absent ⇒ service-level 429. |

Hard rules the gem follows:

- Never hard-code limit values; learn them from `X-*-Rate-Limit` headers and refresh on every response.
- `Retry-After` present ⇒ block for that duration (app-level ⇒ block all requests for the region; method-level ⇒ block only that endpoint bucket).
- `Retry-After` absent ⇒ exponential backoff with jitter (base 1s, factor 2, cap ~32s), bounded by `max_retries`.
- Service-level 429 (no type header) ⇒ back off only the endpoint+region, with a conservative default delay (1–2s).
- Counts from `*-Count` headers are authoritative for the window: the limiter syncs its local counters to them on every response, keeping multi-process consumers roughly aligned.

## 1.4 Response behavior & dynamic endpoints

- Success payloads are JSON; `204 No Content` is a legitimate success (e.g. spectator when nobody is in game) — the gem returns `nil`/empty rather than erroring.
- Riot updates DTOs without notice (new fields appear, occasionally endpoints move version). Consequences for design:
  - Object mapping must be **liberal**: unknown fields are preserved in a raw hash, never dropped.
  - No strict schema validation on read; `raise` only on transport/HTTP failure.
  - Endpoint methods should tolerate 404 as "not found" for lookups (game data is eventually consistent — e.g. a match right after game end can 404 briefly).

## 1.5 Error codes

| Status | Meaning | Gem behavior |
| --- | --- | --- |
| 400 | Bad request (bad params) | raise `Rito::BadRequest` |
| 401 | Unauthorized (bad/expired key) | raise `Rito::Unauthorized` |
| 403 | Forbidden (key revoked, endpoint not entitled) | raise `Rito::Forbidden` |
| 404 | Not found | raise `Rito::NotFound` (helpers may return `nil`) |
| 405 | Method not allowed | raise `Rito::MethodNotAllowed` |
| 415 | Unsupported media type | raise `Rito::UnsupportedMediaType` |
| 429 | Rate limit exceeded | throttle + retry per §1.3, then raise `Rito::RateLimited` |
| 500 | Internal server error | retry (idempotent GETs) then raise `Rito::ServerError` |
| 503 | Service unavailable | retry with backoff, then raise `Rito::ServiceUnavailable` |

## 1.6 Live-tested key behavior (2026-09, `scripts/live_matrix.rb`)

Findings from probing every endpoint with both a development key and a
production personal key (fixtures bootstrapped from `Hide on bush#KR1`):

- **PUUIDs are encrypted per API key.** A puuid minted by one key
  (`by-riot-id`) cannot be read by another key — Riot answers
  `400 "Bad Request - Exception decrypting <puuid>"` on every
  puuid-in-path endpoint. Bootstrap fixtures with the same key you
  query with. Numeric ids (match ids, tournament ids) are not encrypted.
- **Product entitlements gate whole products with a bare 403** (no
  message detail), identically for dev and personal prod keys:
  TFT (tft-*), VALORANT (val-*, incl. console), LoR (lor-*),
  Riftbound, tournament-v5 **and** tournament-stub-v5 (need the
  tournament key product), and account-v1 active-shards.
- **`league-v4 entries/{tier}/{division}` is 403 for personal keys**
  while `league-exp-v4 entries/...` works — Riot restricts the
  full-ladder listing endpoint; use league-exp for ladder browsing.
- tournament-v5/stub read endpoints 403 for non-tournament keys even
  for a syntactically invalid code; there is no "reachable" signal
  without the tournament product.
- RSO endpoints (all `/me`, `lol-rso-match-v1`, `lor-deck-v1`,
  `lor-inventory-v1`) need an RSO bearer token, not an API key.
