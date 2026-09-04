# frozen_string_literal: true

module Rito
  module Endpoints
    module Lol
      class ChampionMasteryV4 < Base
        ROUTING = :platform

        def for_puuid(puuid, region: nil)
          get("/lol/champion-mastery/v4/champion-masteries/by-puuid/#{escape(puuid)}", region)
            .map { |hash| Models::ChampionMastery.from_api(hash) }
        end

        def for_puuid_and_champion(puuid, champion_id, region: nil)
          path = "/lol/champion-mastery/v4/champion-masteries/by-puuid/#{escape(puuid)}" \
                 "/by-champion/#{escape(champion_id)}"
          Models::ChampionMastery.from_api(get(path, region))
        end

        def top_for_puuid(puuid, count: nil, region: nil)
          params = {}
          params['count'] = count if count
          get("/lol/champion-mastery/v4/champion-masteries/by-puuid/#{escape(puuid)}/top", region, params: params)
            .map { |hash| Models::ChampionMastery.from_api(hash) }
        end

        def score(puuid, region: nil)
          get("/lol/champion-mastery/v4/scores/by-puuid/#{escape(puuid)}", region)
        end
      end
    end
  end
end
