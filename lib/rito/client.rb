# frozen_string_literal: true

module Rito
  class Client
    attr_reader :api_key, :bearer_token, :region, :limiter, :max_retries,
                :open_timeout, :timeout, :adapter

    UNSET = Object.new.freeze
    private_constant :UNSET

    def initialize(api_key: UNSET, bearer_token: UNSET, region: nil, rate_limiter: nil,
                   max_retries: nil, open_timeout: nil, timeout: nil, adapter: nil)
      @api_key = api_key.equal?(UNSET) ? (Rito.api_key if bearer_token.equal?(UNSET)) : api_key
      @bearer_token = bearer_token.equal?(UNSET) ? (Rito.bearer_token if api_key.equal?(UNSET)) : bearer_token
      @region = region || Rito.region
      @limiter = rate_limiter || Rito.rate_limiter || RateLimiting::AdaptiveLimiter.new
      @max_retries = max_retries || Rito.max_retries
      @open_timeout = open_timeout || Rito.open_timeout
      @timeout = timeout || Rito.timeout
      @adapter = adapter || Rito.adapter
      @connection = Connection.new(self)

      validate!
    end

    def account
      Endpoints::AccountV1.new(self)
    end

    def summoner
      Endpoints::Lol::SummonerV4.new(self)
    end

    def matches
      Endpoints::Lol::MatchV5.new(self)
    end

    def rso_matches
      Endpoints::Lol::RsoMatchV1.new(self)
    end

    def champion_masteries
      Endpoints::Lol::ChampionMasteryV4.new(self)
    end

    def champions
      Endpoints::Lol::ChampionV3.new(self)
    end

    def leagues
      Endpoints::Lol::LeagueV4.new(self)
    end

    def league_exp
      Endpoints::Lol::LeagueExpV4.new(self)
    end

    def spectator
      Endpoints::Lol::SpectatorV5.new(self)
    end

    def lol_status
      Endpoints::Lol::StatusV4.new(self)
    end

    def clash
      Endpoints::Lol::ClashV1.new(self)
    end

    def challenges
      Endpoints::Lol::ChallengesV1.new(self)
    end

    def tournaments
      Endpoints::Lol::TournamentV5.new(self)
    end

    def tournament_stub
      Endpoints::Lol::TournamentStubV5.new(self)
    end

    def tft
      Rito::Tft::Api.new(self)
    end

    def val
      Rito::Val::Api.new(self)
    end

    def lor
      Rito::Lor::Api.new(self)
    end

    def riftbound
      Endpoints::Riftbound.new(self)
    end

    def request(method, path, routing_kind:, routing_value: nil, regions: nil, params: {}, body: nil)
      region = Routing.resolve(routing_kind, routing_value || @region)
      raise ArgumentError, "#{region.inspect} is not supported by this endpoint" if regions && !regions.include?(region)

      connection = @connection.for_host(Routing.host_for(region))
      context = { attempts: 0 }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      url = connection.build_url(path, params).to_s
      response = connection.run_request(method, path, body, {}) do |req|
        req.options.context = context
        req.params.update(params) unless params.empty?
      end
      # Transport errors and final 5xx must be converted after Faraday's retries.
      raise_server_error!(response) if response.status >= 500
      response
    rescue Faraday::ConnectionFailed => e
      raise ConnectionError.new('Connection failed', wrapped: e)
    rescue Faraday::TimeoutError, ::Timeout::Error => e
      raise TimeoutError.new('Request timed out', wrapped: e)
    rescue Faraday::SSLError => e
      raise SSLError.new('TLS connection failed', wrapped: e)
    ensure
      if context && context[:attempts].positive?
        error = $ERROR_INFO
        Instrumentation.emit(
          http_method: method, url: url,
          status: response&.status || (error.status if error.respond_to?(:status)),
          attempts: context[:attempts],
          duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2),
          error: error&.class&.name
        )
      end
    end

    private

    def raise_server_error!(response)
      status = response.status
      error_class = status == 503 ? ServiceUnavailable : ServerError
      raise error_class.new("#{status} (after transport retries)", response: response)
    end

    def validate!
      raise ConfigError, 'api_key or bearer_token is required' if @api_key.to_s.empty? && @bearer_token.to_s.empty?
      if @api_key && @bearer_token
        raise ConfigError, 'configure either api_key or bearer_token; use separate clients for API and RSO requests'
      end
      return if Routing.platform?(@region) || Routing.regional?(@region) ||
                Routing::VALORANT_PLATFORMS.include?(Routing.normalize(@region))

      raise ConfigError, "unknown region: #{@region.inspect}"
    end
  end
end
