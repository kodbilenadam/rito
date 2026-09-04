# frozen_string_literal: true

# stdlib
require 'json'
require 'uri'
require 'erb/util'

# dependencies
require 'faraday'
require 'faraday/retry'

# modules
require_relative 'rito/routing'
require_relative 'rito/queues'
require_relative 'rito/errors'
require_relative 'rito/rate_limiting/header_parser'
require_relative 'rito/rate_limiting/bucket'
require_relative 'rito/rate_limiting/null_limiter'
require_relative 'rito/rate_limiting/adaptive_limiter'
require_relative 'rito/rate_limiting/redis_limiter'
require_relative 'rito/middleware/authentication'
require_relative 'rito/middleware/rate_limit_throttle'
require_relative 'rito/middleware/rate_limit_observe'
require_relative 'rito/middleware/riot_errors'
require_relative 'rito/connection'
require_relative 'rito/instrumentation'
require_relative 'rito/client'
require_relative 'rito/rso'
require_relative 'rito/models/account'
require_relative 'rito/models/summoner'
require_relative 'rito/models/match'
require_relative 'rito/models/lol'
require_relative 'rito/endpoints/base'
require_relative 'rito/endpoints/account_v1'
require_relative 'rito/endpoints/lol/summoner_v4'
require_relative 'rito/endpoints/lol/match_v5'
require_relative 'rito/endpoints/lol/rso_match_v1'
require_relative 'rito/endpoints/lol/champion_mastery_v4'
require_relative 'rito/endpoints/lol/champion_v3'
require_relative 'rito/endpoints/lol/league_v4'
require_relative 'rito/endpoints/lol/spectator_v5'
require_relative 'rito/endpoints/lol/status_v4'
require_relative 'rito/endpoints/lol/clash_v1'
require_relative 'rito/endpoints/lol/challenges_v1'
require_relative 'rito/endpoints/lol/tournament_v5'
require_relative 'rito/endpoints/tft'
require_relative 'rito/endpoints/valorant'
require_relative 'rito/endpoints/lor'
require_relative 'rito/version'

module Rito
  class << self
    attr_accessor :api_key, :bearer_token, :region, :rate_limiter, :max_retries,
                  :open_timeout, :timeout, :adapter

    def configure
      yield self
      self
    end

    def client(**options)
      Client.new(**options)
    end
  end

  self.api_key = ENV['RIOT_API_KEY']
  self.bearer_token = ENV['RIOT_RSO_TOKEN']
  self.region = :na1
  self.rate_limiter = nil
  self.max_retries = 3
  self.open_timeout = 2
  self.timeout = 10
  self.adapter = Faraday.default_adapter
end
