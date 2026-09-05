# frozen_string_literal: true

module Rito
  module RSO
    Tokens = Data.define(
      :access_token, :id_token, :refresh_token, :token_type, :scope,
      :expires_in, :sub_sid, :raw
    ) do
      def self.from_api(hash)
        new(
          access_token: hash['access_token'],
          id_token: hash['id_token'],
          refresh_token: hash['refresh_token'],
          token_type: hash['token_type'],
          scope: hash['scope'],
          expires_in: hash['expires_in'],
          sub_sid: hash['sub_sid'],
          raw: Models.deep_freeze(hash)
        )
      end

      def id_token_claims
        Jwt.claims(id_token) if id_token
      end

      def refresh_token_claims
        Jwt.claims(refresh_token) if refresh_token
      end
    end

    Userinfo = Data.define(:sub, :cpid, :raw) do
      def self.from_api(hash)
        new(sub: hash['sub'], cpid: hash['cpid'], raw: Models.deep_freeze(hash))
      end
    end

    AuthorizationRequest = Data.define(:url, :state)
  end
end
