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

## Queues

`Rito::Queues` is a frozen, built-in reference for League queue ids as
they appear in match data (match-v5 `queueId`, the `queue` filter on
match lists). Snapshot of the League client's game select data (408 ids).

```ruby
Rito::Queues.find(420).name        # => "Ranked Solo/Duo"
Rito::Queues[450].mode             # => :aram
Rito::Queues.find(2450).limited_time # => true (rotating game mode)
Rito::Queues.select { |q| q.category == :bots }.map(&:name).first(3)

match = client.matches.by_id("NA1_123")
match.info.queue.name              # => "Ranked Flex" (convenience on MatchInfo)
```

Each queue is a frozen `Data` object: `id`, `name`, `short_name`,
`description`, `detailed_description`, `category` (`:pvp`, `:bots`,
`:custom`), `mode` (`:summoners_rift`, `:aram`, `:tft`, `:jade`,
`:other`), `limited_time`, `bot_honoring_allowed`. The module includes
`Enumerable`. Unknown ids return `nil` (Riot adds queues without notice).

## Riot Sign On (RSO)

`Rito::RSO` implements the OAuth2 authorization code flow against
`https://auth.riotgames.com`. Register a client with Riot first; the
redirect URI must be on its allowlist.

```ruby
rso = Rito::RSO::Client.new(
  client_id: ENV.fetch("RIOT_RSO_CLIENT_ID"),
  client_secret: ENV.fetch("RIOT_RSO_CLIENT_SECRET"), # or client_assertion: / private_key:
  redirect_uri: "https://app.example.com/oauth2-callback"
)

# 1. Send the player to Riot; persist request.state to compare on callback
login = rso.authorization_url(login_hint: "na1|daguava")
login.url     # => "https://auth.riotgames.com/authorize?..."
login.state

# 2. Exchange the ?code= query param from the callback for tokens
tokens = rso.exchange_code(params[:code])
tokens.access_token   # Bearer token for RSO resources (encrypted, opaque)
tokens.id_token       # signed JWT identity token
tokens.refresh_token  # signed JWT, self-contained
tokens.expires_in     # 600

# 3. Identify the player
me = rso.userinfo(tokens.access_token)
me.sub    # player sub claim
me.cpid   # "NA1" when the cpid scope was requested

# 4. Rotate when the access token expires
tokens = rso.refresh(tokens.refresh_token)
```

Newer RSO clients authenticate with private-key JWT instead of a secret
(the gem mints a fresh signed assertion per token request):

```ruby
rso = Rito::RSO::Client.new(
  client_id: ENV.fetch("RIOT_RSO_CLIENT_ID"),
  private_key: OpenSSL::PKey::RSA.new(ENV.fetch("RIOT_RSO_PRIVATE_KEY")),
  redirect_uri: "https://app.example.com/oauth2-callback"
)
```

or pass the pre-signed client assertion (the "100 year token") via
`client_assertion:` and treat it like a password.

### Verifying the ID token

```ruby
claims = rso.verify_id_token(tokens.id_token)
claims["sub"] # => signature (RS256 via /jwks.json) + iss/aud/exp validated
```

`verify_id_token` caches the JWKS document and refetches it once when a
`kid` is unknown (Riot rotates keypairs without disabling old ones).
Any failure raises `Rito::RSO::InvalidToken`. Token and userinfo failures
raise `Rito::RSO::OAuthError` with `.error_code` / `.error_description`.

### RSO configuration

```ruby
Rito::RSO.client_id        # default: ENV["RIOT_RSO_CLIENT_ID"]
Rito::RSO.client_secret    # default: ENV["RIOT_RSO_CLIENT_SECRET"]
Rito::RSO.client_assertion # default: ENV["RIOT_RSO_CLIENT_ASSERTION"]
Rito::RSO.private_key
Rito::RSO.redirect_uri     # default: ENV["RIOT_RSO_REDIRECT_URI"]
Rito::RSO.scope            # default: "openid" (add cpid / offline_access)
```

Per-instance kwargs override the module config. Token requests are never
retried (authorization codes and refresh tokens are one-time), so handle
failures explicitly.

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
| `client.account` | account-v1 (accounts, active shards, region, `me` for RSO) |
| `client.summoner` | summoner-v4 (`by_puuid`, `me` for RSO) |
| `client.matches` | match-v5 (matches, matchlist, timeline, replays) |
| `client.rso_matches` | lol-rso-match-v1 (RSO bearer token; player resolved from the token) |
| `client.champion_masteries` | champion-mastery-v4 |
| `client.champions` | champion-v3 (rotations) |
| `client.leagues` / `client.league_exp` | league-v4 / league-exp-v4 |
| `client.spectator` | spectator-v5 (`active_game` returns `nil` on 404) |
| `client.lol_status` | lol-status-v4 |
| `client.clash` | clash-v1 |
| `client.challenges` | lol-challenges-v1 |
| `client.tournaments` / `client.tournament_stub` | tournament-v5 / stub-v5 |
| `client.tft.summoner` / `.leagues` / `.matches` / `.status` / `.spectator` | tft-summoner-v1, tft-league-v1, tft-match-v1, tft-status-v1, spectator-tft-v5 |
| `client.val.content` / `.matches` / `.console_matches` / `.ranked` / `.console_ranked` / `.status` | val-content-v1, val-match-v1, val-console-match-v1, val-ranked-v1, val-console-ranked-v1, val-status-v1 |
| `client.lor.matches` / `.ranked` / `.status` / `.decks` / `.inventory` | lor-match-v1, lor-ranked-v1, lor-status-v1, lor-deck-v1 / lor-inventory-v1 (RSO) |
| `client.riftbound` | riftbound-content-v1 |

Note: VALORANT uses its own platform routing values (`na, eu, ap, kr,
latam, br`; console: `na, eu, ap, br, latam`) — the client validates
against the right set per product. `esports` is a valid platform for
VALORANT content/match and a valid regional for tft-match-v1 (with
`esportseu`); `apac` is a valid regional for lor-match-v1. The
tournament endpoints only exist on the `americas`
platform — pass `region: :na1` or `:americas`.

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
