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

        def by_name(name, region: nil)
          Models::Summoner.from_api(
            get("/lol/summoner/v4/summoners/by-name/#{escape(name)}", region)
          )
        end

        def by_account_id(account_id, region: nil)
          Models::Summoner.from_api(
            get("/lol/summoner/v4/summoners/by-account/#{escape(account_id)}", region)
          )
        end

        def by_summoner_id(summoner_id, region: nil)
          Models::Summoner.from_api(
            get("/lol/summoner/v4/summoners/#{escape(summoner_id)}", region)
          )
        end
      end
    end
  end
end
