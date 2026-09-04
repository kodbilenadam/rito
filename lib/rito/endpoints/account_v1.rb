# frozen_string_literal: true

module Rito
  module Endpoints
    class AccountV1 < Base
      ROUTING = :regional

      def by_riot_id(game_name, tag_line, region: nil)
        Models::Account.from_api(
          get("/riot/account/v1/accounts/by-riot-id/#{escape(game_name)}/#{escape(tag_line)}", region)
        )
      end

      def by_puuid(puuid, region: nil)
        Models::Account.from_api(
          get("/riot/account/v1/accounts/by-puuid/#{escape(puuid)}", region)
        )
      end

      def active_shard(game, puuid, region: nil)
        Models::ActiveShard.from_api(
          get("/riot/account/v1/active-shards/by-game/#{escape(game)}/by-puuid/#{escape(puuid)}", region)
        )
      end

      def region_by_game(game, puuid, region: nil)
        Models::AccountRegion.from_api(
          get("/riot/account/v1/region/by-game/#{escape(game)}/by-puuid/#{escape(puuid)}", region)
        )
      end

      # Requires the client to be configured with a bearer_token (RSO).
      def me(region: nil)
        Models::Account.from_api(get('/riot/account/v1/accounts/me', region))
      end

      private

      def get(path, region)
        # account-v1 has no SEA host; normalize it to ASIA.
        super(path, Routing.regional_for_account(region || @client.region))
      end
    end
  end
end
