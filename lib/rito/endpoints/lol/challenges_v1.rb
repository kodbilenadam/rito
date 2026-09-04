# frozen_string_literal: true

module Rito
  module Endpoints
    module Lol
      class ChallengesV1 < Base
        ROUTING = :platform

        def config(region: nil)
          get('/lol/challenges/v1/challenges/config', region)
        end

        def challenge_config(challenge_id, region: nil)
          get("/lol/challenges/v1/challenges/#{escape(challenge_id)}/config", region)
        end

        def percentiles(region: nil)
          get('/lol/challenges/v1/challenges/percentiles', region)
        end

        def challenge_percentiles(challenge_id, region: nil)
          get("/lol/challenges/v1/challenges/#{escape(challenge_id)}/percentiles", region)
        end

        def leaderboard(challenge_id, level, limit: nil, region: nil)
          params = {}
          params['limit'] = limit if limit
          get("/lol/challenges/v1/challenges/#{escape(challenge_id)}/leaderboards/by-level/#{escape(level)}", region,
              params: params)
        end

        def player_data(puuid, region: nil)
          get("/lol/challenges/v1/player-data/#{escape(puuid)}", region)
        end
      end
    end
  end
end
