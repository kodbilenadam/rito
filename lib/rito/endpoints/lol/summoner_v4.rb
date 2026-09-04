# frozen_string_literal: true

module Rito
  module Endpoints
    module Lol
      class SummonerV4 < Base
        ROUTING = :platform

        def by_puuid(puuid, region: nil)
          Models::Summoner.from_api(
            get("/lol/summoner/v4/summoners/by-puuid/#{escape(puuid)}", region)
          )
        end

        # Requires the client to be configured with a bearer_token (RSO).
        def me(region: nil)
          Models::Summoner.from_api(get('/lol/summoner/v4/summoners/me', region))
        end
      end
    end
  end
end
