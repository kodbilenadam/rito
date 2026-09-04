# frozen_string_literal: true

module Rito
  class Client
    attr_reader :api_key, :bearer_token, :region, :limiter, :max_retries,
                :open_timeout, :timeout, :adapter

    def initialize(api_key: nil, bearer_token: nil, region: nil, rate_limiter: nil,
                   max_retries: nil, open_timeout: nil, timeout: nil, adapter: nil)
      @api_key = api_key || Rito.api_key
      @bearer_token = bearer_token || Rito.bearer_token
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

    def request(method, path, routing_kind:, routing_value: nil, params: {}, body: nil)
      region = Routing.resolve(routing_kind, routing_value || @region)
      connection = @connection.for_host(Routing.host_for(region))
      response = connection.run_request(method, path, body, {}) do |req|
        req.params.update(params) unless params.empty?
      end
      # 5xx responses reaching here are final: faraday-retry has exhausted
      # its retries (or the status was not retryable).
      raise_server_error!(response) if response.status >= 500
      response
    end

    private

    def raise_server_error!(response)
      status = response.status
      error_class = status == 503 ? ServiceUnavailable : ServerError
      raise error_class.new("#{status} (after transport retries)", response: response)
    end

    def validate!
      raise ConfigError, 'api_key or bearer_token is required' if @api_key.to_s.empty? && @bearer_token.to_s.empty?
      return if Routing.platform?(@region) || Routing.regional?(@region)

      raise ConfigError, "unknown region: #{@region.inspect}"
    end
  end
end
