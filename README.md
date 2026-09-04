# Rito

A modern, production-ready Ruby client for the Riot Games API: League of
Legends, TFT, VALORANT, Legends of Runeterra, Riftbound, and the Riot Account API.

Full routing-value handling, header-driven adaptive rate limiting, frozen
`Data` models, and a single runtime dependency (Faraday).

## Installation

```ruby
gem "rito"
```

## Quick start

```ruby
require "rito"

Rito.configure do |c|
  c.api_key = ENV.fetch("RIOT_API_KEY")
  c.region = :na1
end

client = Rito::Client.new

account = client.account.by_riot_id("Hide on bush", "KR1", region: :asia)
summoner = client.summoner.by_puuid(account.puuid, region: :kr)
match_ids = client.matches.ids_by_puuid(account.puuid, region: :asia, count: 5)
```

## Configuration

Class-level config with per-client overrides (later wins):

```ruby
Rito.api_key        # default: ENV["RIOT_API_KEY"]
Rito.bearer_token   # default: ENV["RIOT_RSO_TOKEN"] (RSO endpoints)
Rito.region         # default routing value, e.g. :na1
Rito.max_retries    # 429 / transport retries (default: 3)
Rito.rate_limiter   # rate limit strategy (default: AdaptiveLimiter)

# per-client, for multi-key apps:
client = Rito::Client.new(api_key: "RGAPI-...", region: :kr)
```

## Routing values

Endpoints declare whether they are platform-routed (`na1`, `kr`, ...) or
regionally routed (`americas`, `europe`, `asia`, `sea`). You pass whichever you
have; the client escalates automatically:

```ruby
client.summoner.by_puuid(puuid, region: :kr)         # platform host: kr
client.matches.ids_by_puuid(puuid, region: :kr)      # regional host: asia (escalated)
client.account.by_puuid(puuid, region: :sea)         # account-v1 has no SEA host → asia
```

## Rate limiting

The default `AdaptiveLimiter` learns your key's limits from
`X-App-Rate-Limit` / `X-Method-Rate-Limit` headers, syncs counters from
`*-Count` headers, throttles pre-emptively, and handles 429s:

- `Retry-After` present → blocks that long (app-scope blocks the whole
  key+region; method-scope blocks only the endpoint).
- `Retry-After` missing → exponential backoff with jitter.
- No `X-Rate-Limit-Type` header → service-level 429 → endpoint-only backoff.

Exhausted retries raise `Rito::RateLimited` (with `.retry_after` and
`.limit_type`). Opt out with `Rito::RateLimiting::NullLimiter`.

### Multi-worker deployments

Each process using the default `AdaptiveLimiter` tracks limits independently,
so a multi-worker setup (Puma cluster, multiple hosts) can collectively exceed
one key's limits. Use the Redis limiter for shared state:

```ruby
limiter = Rito::RateLimiting::RedisLimiter.new(redis: Redis.new)
client = Rito::Client.new(rate_limiter: limiter)
```

Note: `acquire!` blocks the calling thread while throttled — fine in
background jobs; in web requests prefer jobs or `max_retries: 0` with
explicit `Rito::RateLimited` handling.

### Multi-process (Redis)

```ruby
gem "redis" # soft dependency

limiter = Rito::RateLimiting::RedisLimiter.new(redis: Redis.new)
client = Rito::Client.new(rate_limiter: limiter)
```

## Errors

```
Rito::Error
├── BadRequest (400)          ├── MethodNotAllowed (405)
├── Unauthorized (401)        ├── UnsupportedMediaType (415)
├── Forbidden (403)           ├── RateLimited (429)
├── NotFound (404)            ├── ServerError / ServiceUnavailable (5xx)
└── ConnectionError (TimeoutError, SSLError)
```

Every error carries `.status` and `.response`. Messages include the method,
URL, and Riot's error detail.

## Models

Responses are frozen `Data` objects. Documented fields are typed accessors;
unknown fields Riot adds later are preserved in `.raw`:

```ruby
entry = client.leagues.entries_by_summoner_id(summoner_id).first
entry.tier      # => "DIAMOND"
entry.winrate   # => 57.14
entry.raw       # => full payload hash
```

## Coverage

| Accessor | API |
| --- | --- |
| `client.account` | account-v1 |
| `client.summoner` | summoner-v4 |
| `client.matches` | match-v5 (matches, matchlist, timeline) |
| `client.champion_masteries` | champion-mastery-v4 |
| `client.champions` | champion-v3 (rotations) |
| `client.leagues` / `client.league_exp` | league-v4 / league-exp-v4 |
| `client.spectator` | spectator-v5 (`active_game` returns `nil` on 404) |
| `client.lol_status` | lol-status-v4 |
| `client.clash` | clash-v1 |
| `client.challenges` | lol-challenges-v1 |
| `client.tournaments` / `client.tournament_stub` | tournament-v5 / stub-v5 |
| `client.tft.summoner` / `.leagues` / `.matches` / `.status` / `.spectator` | tft-summoner-v1, tft-league-v1, tft-match-v1, tft-status-v1, spectator-tft-v5 |
| `client.val.content` / `.matches` / `.console_matches` / `.ranked` / `.status` | val-content-v1, val-match-v1, val-console-match-v1, val-ranked-v1, val-status-v1 |
| `client.lor.matches` / `.ranked` / `.status` / `.decks` / `.inventory` | lor-match-v1, lor-ranked-v1, lor-status-v1, lor-deck-v1 / lor-inventory-v1 (RSO) |
| `client.riftbound` | riftbound-content-v1 |

Note: VALORANT uses its own platform routing values (`na1, eu, ap, kr, latam, br`;
console: `na, eu, ap`) — the client validates against the right set per product.

## Testing your own app

`Rito` plays well with WebMock. Recorded fixtures via VCR:

```
bundle exec rake cassettes   # re-record (needs RIOT_API_KEY_TEST in .env)
bundle exec rake test
```

## Instrumentation

If ActiveSupport is present (e.g. in a Rails app), every request emits a
`request.rito` notification:

```ruby
ActiveSupport::Notifications.subscribe("request.rito") do |*, payload|
  Rails.logger.info(
    "#{payload[:http_method]} #{payload[:url]} -> #{payload[:status]} " \
    "in #{payload[:duration_ms]}ms (attempts: #{payload[:attempts]})"
  )
end
```

Without ActiveSupport, instrumentation is a no-op.

## Development

```
bundle install
bundle exec rake test
```

Ruby 3.2+ required (`Data.define`).

## License

MIT
