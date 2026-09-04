# Rito — Architecture Proposal

A modern, production-ready Ruby gem for the Riot Games API.
Working name: **`rito`** (module `Rito`). Target: Ruby 3.2+.

---

## 1. API & Infrastructure Research

### 1.1 Routing values

Riot routes every request through two kinds of hosts. An endpoint is bound to one of the two — this is the single most common integration bug, so it becomes a first-class concept in the gem, not a string the user passes around.

**Platform routing values** (service topology, e.g. `na1.api.riotgames.com`):
`BR1, EUN1, EUW1, JP1, KR, LA1, LA2, ME1, NA1, OC1, PH2, RU, SG2, TH2, TR1, TW2, VN2`

**Regional (cluster) routing values** (e.g. `americas.api.riotgames.com`):
`AMERICAS, ASIA, EUROPE, SEA`

Platform → regional cluster mapping (used for automatic escalation, e.g. resolving a summoner on `na1` then fetching matches on `americas`):

| Regional | Platforms |
| --- | --- |
| AMERICAS | NA1, BR1, LA1, LA2 |
| EUROPE | EUW1, EUN1, TR1, RU, ME1 |
| ASIA | KR, JP1 |
| SEA | OC1, SG2, TW2, VN2, PH2, TH2 |

Gotchas encoded into the gem:

- **account-v1** serves only `AMERICAS / EUROPE / ASIA` — there is no SEA host; `sea` accounts must be queried via `asia`. The routing table normalizes this.
- Some endpoints are pinned differently per game (e.g. `summoner-v4` is platform-routed; `match-v5` is regional-routed; VALORANT `val-match-v1` is platform-routed).
- Each endpoint module declares its routing kind (`:platform` or `:regional`) so the client resolves the correct host automatically and can escalate `na1 → americas` transparently.

### 1.2 Auth

- Production/personal keys: header `X-Riot-Token: <key>`.
- RSO / OAuth endpoints (`/accounts/me`, `lol-rso-match-v1`, `lor-deck-v1`): header `Authorization: Bearer <accessToken>`. The gem supports a key **or** a bearer token per client; `accounts/me`-style endpoints accept a per-call token override.

### 1.3 Rate limiting model

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

### 1.4 Response behavior & dynamic endpoints

- Success payloads are JSON; `204 No Content` is a legitimate success (e.g. spectator when nobody is in game) — the gem returns `nil`/empty rather than erroring.
- Riot updates DTOs without notice (new fields appear, occasionally endpoints move version). Consequences for design:
  - Object mapping must be **liberal**: unknown fields are preserved in a raw hash, never dropped.
  - No strict schema validation on read; `raise` only on transport/HTTP failure.
  - Endpoint methods should tolerate 404 as "not found" for lookups (game data is eventually consistent — e.g. a match right after game end can 404 briefly).

### 1.5 Error codes

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

---

## 2. Gem Architecture & Best Practices

### 2.1 Prior-art analysis

| Gem | Verdict | Takeaways |
| --- | --- | --- |
| `ruby-lol` (mikamai) | Stale, LoL-only, v3 endpoints | OpenStruct mapping is convenient but slow and typo-tolerant in a bad way (no method errors). |
| `taric` (josephyi) | Stale, Faraday+Typhoeus, v3 | Good Faraday integration pattern; adapter-swap idea worth keeping. |
| `riot-api` (Anujan), `riot_lol_api` | Stale, LoL-only | Global constant API key config is an anti-pattern (no multi-key, thread safety). |
| `riot_api` (he9qi) | Stale, registry/strategy pattern | Registry pattern adds indirection without benefit. |

**Gap:** no maintained gem covers the full multi-game surface (LoL, TFT, VALORANT, LoR, Account, Riftbound), modern routing values, header-driven rate limiting, or multi-key/multi-process throttling. Rito fills it.

### 2.2 HTTP layer — **Faraday 2.x** (recommended)

Rationale:

- **Middleware stack** maps 1:1 onto our cross-cutting concerns: auth header, rate-limit observation, throttling, retry, logging, JSON parsing — each a small, testable, composable middleware.
- **Adapter swappability**: default `net_http` (keep-alive, persistent per-connection object); users can opt into `typhoeus` (libcurl, true parallelism), `httpx` (HTTP/2, fibers, async), or `faraday_connection_pool` (pooled persistent connections) without gem changes. Our own code never touches the adapter API.
- **`faraday-retry`** handles transport-level retries (connection failures, 5xx) while our custom middleware owns 429 semantics — clean separation of concerns.
- Mature, actively maintained, Ruby 3.0+ supported, battle-tested in production gems.

Rejected alternatives: `http.rb` (great ergonomics but no middleware ecosystem — we'd rebuild retry/instrumentation ourselves), `HTTParty` (no middleware), raw `Net::HTTP` (maintenance burden).

**Connection model:** one cached Faraday connection **per routing value** (host), lazily built from the shared middleware template ⇒ persistent keep-alive connections, no per-request TCP+TLS setup. Timeouts: `open_timeout: 2s`, `timeout: 10s` (configurable).

### 2.3 Object mapping — frozen **Data classes** (Ruby 3.2 `Data.define`)

- **Chosen:** lightweight `Data` classes with class-level `from_api(hash)` constructors. Idiomatic, immutable, fast, pattern-matchable, IDE/YARD-friendly, exact-method errors.
- **Not** Hashie/OpenStruct: method-missing-based mappers are slow, hide nil bugs, and break `respond_to?` reasoning.
- **Not** plain hashes as the primary interface: no discoverability. But raw access is preserved: every model exposes `.raw` (the parsed payload) so unknown/new fields are never lost, and `.from_api` copies known fields plus the rest into `raw`.
- Models are **thin and liberal**: they declare typed getters for documented fields, default missing values to `nil`, and keep everything else in `raw`.
- Escape hatch: `Rito::Client#get` returns the parsed hash for unmodeled endpoints.

### 2.4 Configuration

Three layers, later wins:

1. Environment: `RIOT_API_KEY` (also `RIOT_RSO_TOKEN` for RSO apps).
2. Global: `Rito.configure { |c| c.api_key = ... }` — frozen snapshot, thread-safe (mutex-guarded swap), suitable for Rails initializer.
3. Instance: `Rito::Client.new(api_key:, region: :na1, ...)` — for multi-key/multi-tenant apps.

Config surface: `api_key`, `bearer_token`, `region` (default routing value), `rate_limiter` (strategy instance, default `AdaptiveLimiter`), `max_retries`, `open_timeout`, `timeout`, `adapter` (symbol/class), `logger`, `middleware` (proc to append custom Faraday middleware). All values validated at configure time (fail fast on bad routing value, nil key, etc.).

---

## 3. Module & Endpoint Coverage Plan

### 3.1 Namespacing strategy

One namespace per game, one class per API version — mirrors the portal's API list (verified against developer.riotgames.com/apis, Sep 2026):

```
Rito::AccountV1            # account-v1 (regional; AMERICAS/EUROPE/ASIA only)
Rito::LeagueOfLegends
  ├── ChampionMasteryV4    # champion-mastery-v4 (platform)
  ├── ChampionV3           # champion-v3 (platform)
  ├── ClashV1              # clash-v1 (platform)
  ├── LeagueV4             # league-v4, league-exp-v4 (platform)
  ├── ChallengesV1         # lol-challenges-v1 (platform)
  ├── MatchV5              # match-v5 (regional)
  ├── RsoMatchV1           # lol-rso-match-v1 (regional, RSO bearer)
  ├── SpectatorV5          # spectator-v5 (platform)
  ├── StatusV4             # lol-status-v4 (platform)
  ├── SummonerV4           # summoner-v4 (platform)
  └── TournamentV5         # tournament-v5 + tournament-stub-v5 (platform)
Rito::Tft                  # tft-league-v1, tft-match-v1 (regional),
                           # tft-summoner-v1, spectator-tft-v5, tft-status-v1 (platform)
Rito::Valorant             # val-content-v1, val-match-v1, val-ranked-v1,
                           # val-status-v1 (platform); val-console-* (platform)
Rito::Lor                 # lor-match-v1, lor-ranked-v1 (regional);
                          # lor-status-v1 (regional); lor-deck-v1, lor-inventory-v1 (RSO)
Rito::Riftbound            # riftbound-content-v1 (regional)
```

Out of scope for v1.0 (documented as such): Data Dragon / Community Dragon static assets (separate tiny gem or plain URLs), LoL Esports API, Riot OAuth flow implementation (we accept tokens; we don't mint them).

### 3.2 Method naming conventions

- **Noun-first, HTTP-agnostic:** `SummonerV4#by_puuid`, `MatchV5#by_id`, `MatchV5#ids_by_puuid`, `LeagueV4#entries_by_summoner_id`. No `get_`, no `fetch_` prefixes, verbs only where unavoidable (`create_tournament_codes`).
- **Keyword-only parameters**, snake_cased to match the portal docs (e.g. `queue:`, `start:`, `count:`), URL-escaped path segments, arrays → `?a=1&a=2` query params.
- **`region:` keyword on every call**, resolved against the endpoint's routing kind: passing a platform to a regional endpoint auto-escalates (`:na1 → :americas`); passing a region to a platform endpoint raises `ArgumentError` unless resolvable down (ambiguity: `:americas` cannot pick a platform → `ArgumentError`).
- Cross-referencing flows get sugar: `Rito::MatchV5#by_puuid` handles the summoner→puuid→matches chain only as documentation, not magic.

### 3.3 Dynamic endpoint updates

- Endpoint declarations live in one table per API class (path template + routing kind + rate-limit bucket name) — adding/moving an endpoint is a one-line change.
- `X-Rate-Limit-Type` buckets are keyed by `bucket = method_id + routing_value`, matching Riot's per-endpoint counting.
- Versioned response models never reject unknown keys ⇒ Riot adding fields is a non-event for the gem.

---

## 4. Resiliency & Developer Experience

### 4.1 Exception hierarchy

```
Rito::Error < StandardError                # .response (Faraday::Response), .status
├── Rito::BadRequest          (400)
├── Rito::Unauthorized        (401)
├── Rito::Forbidden           (403)
├── Rito::NotFound            (404)
├── Rito::MethodNotAllowed    (405)
├── Rito::UnsupportedMediaType(415)
├── Rito::RateLimited         (429)        # .retry_after, .limit_type (:application/:method/:service), .bucket
├── Rito::ServerError         (5xx)        # ServiceUnavailable (503) subclasses it
└── Rito::ConnectionError                  # .wrapped (Faraday::ConnectionFailed/TimeoutError etc.)
    ├── Rito::TimeoutError
    └── Rito::SSLError
```

`429` and `5xx` are retried inside the middleware **before** surfacing, so users only see them when retries are exhausted. `404` is retried never. All errors include the request context (method, URL, routing value) in the message.

### 4.2 Rate-limit strategies (pluggable)

`Rito::RateLimiting::Limiter` protocol: `acquire!(key, region, method_id)` (blocks until allowed) and `observe!(response, key, region, method_id)` (syncs from headers).

| Strategy | Use case |
| --- | --- |
| `NullLimiter` | Default-free option; rely purely on reactive 429 handling. Default in tests. |
| `AdaptiveLimiter` | Default in production. In-process token buckets per (key, region) app-level and (key, region, method) method-level, built from header-declared windows; `Concurrent::Map` + atomics ⇒ thread-safe, fiber-friendly (no sleeping locks). Pre-emptively throttles before limits hit; 429s become near-non-events. |
| `RedisLimiter` (opt-in dependency `redis`) | Multi-process/multi-host apps. Sliding-window counters in Redis keyed `rito:{api_key_hash}:{region}:{bucket}`; local `Retry-After` block via a small TTL key. Lua script for atomic check-and-increment. |

Adaptive details:

- Windows learned from `X-App-Rate-Limit` / `X-Method-Rate-Limit` on first response; never hard-coded.
- On every response, `*-Count` headers sync counters (max(local, header) within live windows).
- On 429: `blocked_until` per bucket scope (application ⇒ whole key+region; method ⇒ endpoint; service ⇒ endpoint, default 2s when `Retry-After` missing).
- Retry loop: honor block, then `acquire!` again; `max_retries` (default 3) then raise `RateLimited`.

### 4.3 Logging & debugging

- Faraday `:instrumentation` middleware wrapping `ActiveSupport::Notifications` (`request.rito` / `response.rito` events) with a pluggable `logger` (falls back to a no-op).
- Custom middleware attaches response meta (`Rito::Meta`: latency, rate-limit counts, remaining, request id) to every model object — users can inspect throttling behavior in prod.
- `DEBUG=1` / `logger.level = :debug` logs sanitized headers (key redacted) and bodies; header/body logging off by default.

### 4.4 Test mocking strategy

- **WebMock** as the base stubbing layer (`webmock/disable_net_connect`), helpers in `Rito::SpecHelpers` exported for downstream users who want to stub without recording.
- **VCR** cassettes recorded once per endpoint × routing-value family, checked in; credentials stripped via filter (`RGAPI-…`).
- Rate limiter unit tests use synthetic header fixtures (frozen in `spec/fixtures/headers.yml`), including the "Retry-After missing" regression case.
- A `FakeRiotApi` Rack app for integration tests of the full client pipeline without network.
- CI: matrix over supported Rubies (3.2/3.3/3.4/head), `rubocop`, `standardrb`, `steep`/`rbs` optional.

---

## 5. Implementation Plan & Code Blueprint

### 5.1 Directory structure

```
rito-api/
├── lib/
│   ├── rito.rb                        # entry point: version, config DSL, client builder
│   └── rito/
│       ├── version.rb
│       ├── configuration.rb
│       ├── client.rb                  # request pipeline owner
│       ├── connection.rb              # Faraday stack builder, per-host cache
│       ├── routing.rb                 # routing values, platform↔regional tables, host resolution
│       ├── meta.rb                    # response metadata (limits, latency)
│       ├── errors.rb
│       ├── model.rb                   # base Data model with .from_api / .raw
│       ├── rate_limiting/
│       │   ├── limiter.rb             # protocol
│       │   ├── null_limiter.rb
│       │   ├── adaptive_limiter.rb
│       │   ├── header_parser.rb
│       │   └── redis_limiter.rb       # optional dependency
│       ├── middleware/
│       │   ├── authentication.rb
│       │   ├── rate_limit_observe.rb
│       │   ├── rate_limit_throttle.rb
│       │   ├── riot_errors.rb         # 4xx/5xx → Rito::Error
│       │   └── instrumented.rb
│       ├── endpoints/                 # one file per API, declarative table
│       │   ├── account_v1.rb
│       │   ├── lol/summoner_v4.rb
│       │   ├── lol/match_v5.rb
│       │   └── ...
│       └── models/
│           ├── account.rb
│           ├── lol/summoner.rb
│           └── ...
├── spec/
│   ├── support/ (webmock helpers, header fixtures)
│   ├── vcr_cassettes/
│   ├── rito/{configuration,routing,client}_spec.rb
│   ├── rito/rate_limiting/*
│   └── rito/endpoints/*
├── .rubocop.yml / .standard.yml
├── rito.gemspec
├── Gemfile
└── README.md
```

### 5.2 Blueprint code

```ruby
# lib/rito/routing.rb
module Rito
  module Routing
    PLATFORMS = %w[br1 eun1 euw1 jp1 kr la1 la2 me1 na1 oc1 ph2 ru sg2 th2 tr1 tw2 vn2].freeze
    REGIONALS = %w[americas asia europe sea].freeze

    CLUSTERS = {
      "americas" => %w[na1 br1 la1 la2],
      "europe"   => %w[euw1 eun1 tr1 ru me1],
      "asia"     => %w[kr jp1],
      "sea"      => %w[oc1 sg2 tw2 vn2 ph2 th2]
    }.freeze

    ACCOUNT_REGIONALS = %w[americas asia europe].freeze # no SEA host; sea → asia

    class << self
      def platform?(value)   = PLATFORMS.include?(normalize(value))
      def regional?(value)   = REGIONALS.include?(normalize(value))
      def normalize(value)   = value.to_s.downcase

      def host_for(value)
        v = normalize(value)
        case v
        when *PLATFORMS then "#{v}.api.riotgames.com"
        when *REGIONALS then "#{v}.api.riotgames.com"
        else raise ArgumentError, "unknown routing value: #{value.inspect}"
        end
      end

      # Endpoint declares :platform or :regional. Resolve user input accordingly.
      def resolve(routing_kind, value)
        v = normalize(value)
        return v if routing_kind == :platform && platform?(v)
        return v if routing_kind == :regional && regional?(v)

        if routing_kind == :regional && platform?(v)
          CLUSTERS.each { |regional, platforms| return regional if platforms.include?(v) }
        end
        raise ArgumentError, "#{value.inspect} is not usable as a #{routing_kind} routing value"
      end

      def regional_for_account(value)
        v = normalize(value)
        return v if ACCOUNT_REGIONALS.include?(v)
        v == "sea" ? "asia" : resolve(:regional, v)
      end
    end
  end
end
```

```ruby
# lib/rito/configuration.rb
module Rito
  class Configuration
    attr_accessor :api_key, :bearer_token, :region, :rate_limiter, :max_retries,
                  :open_timeout, :timeout, :adapter, :logger, :middleware

    def initialize
      @api_key      = ENV["RIOT_API_KEY"]
      @bearer_token = ENV["RIOT_RSO_TOKEN"]
      @region       = :na1
      @rate_limiter = RateLimiting::AdaptiveLimiter.new
      @max_retries  = 3
      @open_timeout = 2
      @timeout      = 10
      @adapter      = Faraday.default_adapter
      @logger       = nil
      @middleware   = nil
    end

    def validate!
      raise ConfigError, "api_key or bearer_token required" if api_key.to_s.empty? && bearer_token.to_s.empty?
      Routing.normalize(region)
      self
    end
  end

  class << self
    def configure
      @mutex ||= Mutex.new
      config = Configuration.new
      yield config
      @mutex.synchronize { @config = config.validate! }
    end

    def config
      @mutex.synchronize { @config } || raise(ConfigError, "call Rito.configure first or pass options to Client.new")
    end
  end
end
```

```ruby
# lib/rito/connection.rb
module Rito
  class Connection
    def initialize(config) = @config = config
    def config = @config

    def for_host(host) = (@connections ||= Concurrent::Map.new).compute_ifAbsent(host) { build(host) }

    private

    def build(host)
      Faraday.new("https://#{host}", request: { open_timeout: @config.open_timeout, timeout: @config.timeout }) do |f|
        f.request :json
        f.use Middleware::RateLimitThrottle, config: @config
        f.use Middleware::Authentication,    config: @config
        f.use Middleware::RateLimitObserve,  config: @config
        f.use Middleware::RiotErrors,        config: @config
        f.request :retry, max: @config.max_retries, retry_statuses: [500, 503, 504],
                          interval: 0.5, backoff_factor: 2,
                          exceptions: [Faraday::ConnectionFailed, Faraday::TimeoutError]
        f.response :json, content_type: /\bjson$/
        f.use Middleware::Instrumented, config: @config, logger: @config.logger
        @config.middleware&.call(f)
        f.adapter @config.adapter
      end
    end
  end
end
```

```ruby
# lib/rito/client.rb
module Rito
  class Client
    attr_reader :config

    def initialize(**overrides)
      @config = overrides.empty? ? Rito.config : build_config(overrides)
      @connection = Connection.new(@config)
    end

    def account  = Endpoints::AccountV1.new(self)
    def summoner = Endpoints::Lol::SummonerV4.new(self)
    def matches  = Endpoints::Lol::MatchV5.new(self)
    # ... tft, valorant, lor, riftbound accessors

    # routing_kind: :platform | :regional — declared by the endpoint module
    def request(method:, path:, routing_kind:, routing_value:, params: {}, bucket: nil, raw: false)
      region = Routing.resolve(routing_kind, routing_value || @config.region)
      host   = Routing.host_for(region)
      bucket ||= "#{path.split("/")[1..2].join("/")}"

      response = @connection.for_host(host).send(method, path, params)
      body = response.body
      raw ? body : response
    end
  end
end
```

```ruby
# lib/rito/endpoints/account_v1.rb  (complete reference implementation)
module Rito
  module Endpoints
    class AccountV1
      ROUTING = :regional

      def initialize(client) = @client = client

      # GET /riot/account/v1/accounts/by-riot-id/{gameName}/{tagLine}
      def by_riot_id(game_name, tag_line, region: nil, raw: false)
        model Account.by_riot_id(
          escape(game_name), escape(tag_line),
          region: Routing.regional_for_account(region || @client.config.region), raw: raw
        )
      end

      def by_puuid(puuid, region: nil, raw: false)
        Account.from_api get("/riot/account/v1/accounts/by-puuid/#{escape(puuid)}", region)
      end

      # GET /riot/account/v1/active-shards/by-game/{game}/by-puuid/{puuid}
      def active_shard(game, puuid, region: nil)
        Models::ActiveShard.from_api(
          get("/riot/account/v1/active-shards/by-game/#{game}/by-puuid/#{escape(puuid)}", region)
        )
      end

      private

      def get(path, region)
        @client.request(method: :get, path: path, routing_kind: ROUTING, routing_value: region)
      end

      def escape(segment) = ERB::Util.url_encode(segment)
    end
  end
end
```

```ruby
# lib/rito/models/account.rb
module Rito
  module Models
    Account = Data.define(:puuid, :game_name, :tag_line, :raw) do
      def self.from_api(hash)
        new(
          puuid: hash["puuid"],
          game_name: hash["gameName"],
          tag_line: hash["tagLine"],
          raw: hash.freeze
        )
      end
    end

    ActiveShard = Data.define(:puuid, :game, :active_shard, :raw) do
      def self.from_api(hash)
        new(puuid: hash["puuid"], game: hash["game"],
            active_shard: hash["activeShard"], raw: hash.freeze)
      end
    end
  end
end
```

```ruby
# lib/rito/rate_limiting/adaptive_limiter.rb  (shape; full impl in implementation phase)
module Rito
  module RateLimiting
    class AdaptiveLimiter
      def initialize = (@buckets = Concurrent::Map.new)

      # Block until the (app or method) bucket allows one more call.
      def acquire!(key, region, bucket)
        app = bucket_for("app", key, region)
        method = bucket_for("method", key, region, bucket)
        [app, method].each { |b| b.wait_until_allowed! }
      end

      # Sync counters/windows/blocked_until from a Faraday response.
      def observe!(response, key, region, bucket)
        HeaderParser.parse(response).each { |scope, update| bucket_for(...).apply!(update) }
      end

      private

      def bucket_for(scope, key, region, method_id = nil)
        @buckets.compute_ifAbsent([scope, key, region, method_id]) { Bucket.new }
      end
    end
  end
end
```

**Public API sketch (final DX):**

```ruby
require "rito"

Rito.configure do |c|
  c.api_key = ENV.fetch("RIOT_API_KEY")
  c.region  = :na1
end

client = Rito::Client.new

account = client.account.by_riot_id("Faker", "KR1")            # → Rito::Models::Account
sum     = client.summoner.by_puuid(account.puuid)              # platform-routed: na1
matches = client.matches.ids_by_puuid(account.puuid,
                                      region: :americas, count: 20)

begin
  client.matches.by_id("KR_123456")
rescue Rito::RateLimited => e
  sleep e.retry_after
end
```

### 5.3 Phased plan

| Phase | Scope | Exit criteria |
| --- | --- | --- |
| **P0 — Core** | Gem scaffold, config, routing, connection/middleware stack, errors, Meta, logging | `SummonerV4#by_puuid` works against live API behind WebMock; CI green |
| **P1 — Rate limiting** | HeaderParser, AdaptiveLimiter, throttle/observe middleware, NullLimiter, retry loop incl. missing Retry-After | 429 storm fixture exhausts 0 errors, 0 retries on replay; race tests (threads × 100 calls) stay within learned limits |
| **P2 — LoL + Account** | SummonerV4, MatchV5, LeagueV4/EXP, ChampionMasteryV4, SpectatorV5, StatusV4, ClashV1, ChallengesV1, TournamentV5 + models + VCR cassettes | Full LoL surface covered, documented |
| **P3 — Other games** | TFT, VALORANT, LoR, Riftbound, RSO bearer endpoints | Same |
| **P4 — Scale features** | RedisLimiter, adapter recipes (Typhoeus/httpx), streaming/pagination helpers, rubocop+yard 100% documented public API | Docs + changelog + 1.0 release |

Release process: `steep`/`rbs` signatures optional behind `sig/`, conventional commits, `bundler/gem_tasks`, YARD + a `docs/` folder mirroring the portal per-API pages.

---

## Open questions for refinement

1. **Default limiter on/off:** ship `AdaptiveLimiter` enabled by default, or `NullLimiter` default with an explicit opt-in? (Recommendation: enabled by default — safer for naive users; it's a no-op until first headers arrive.)
2. **Ruby floor:** 3.2 (for `Data.define`) acceptable, or support 3.1 with `Struct`?
3. **Redis dependency:** optional `rumount` (soft) dependency vs separate `rito-redis` gem? (Recommendation: soft dependency, `Rito.use_redis!` raises with guidance until `redis` is bundled.)
4. **Concurrency:** ship a `fiber`-friendly batch API (`Rito::Batch` using `Fiber.await` with httpx) in 1.0 or defer to 1.1?
