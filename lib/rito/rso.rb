# frozen_string_literal: true

require 'openssl'
require 'securerandom'

module Rito
  module RSO
    JWT_BEARER_TYPE = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'

    class << self
      attr_accessor :provider, :client_id, :client_secret, :client_assertion,
                    :private_key, :redirect_uri, :scope
    end

    self.provider = 'https://auth.riotgames.com'
    self.client_id = ENV['RIOT_RSO_CLIENT_ID']
    self.client_secret = ENV['RIOT_RSO_CLIENT_SECRET']
    self.client_assertion = ENV['RIOT_RSO_CLIENT_ASSERTION']
    self.private_key = nil
    self.redirect_uri = ENV['RIOT_RSO_REDIRECT_URI']
    self.scope = 'openid'
  end
end

require_relative 'rso/errors'
require_relative 'rso/jwt'
require_relative 'rso/jwks'
require_relative 'rso/models'
require_relative 'rso/credential'
require_relative 'rso/client'
