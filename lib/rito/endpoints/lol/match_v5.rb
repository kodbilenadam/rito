# frozen_string_literal: true

module Rito
  module Endpoints
    module Lol
      class MatchV5 < Base
        ROUTING = :regional

        def by_id(match_id, region: nil)
          Models::Match.from_api(
            get("/lol/match/v5/matches/#{escape(match_id)}", region)
          )
        end

        def ids_by_puuid(puuid, region: nil, start: nil, count: nil, queue: nil,
                         type: nil, start_time: nil, end_time: nil)
          params = {}
          params['start'] = start if start
          params['count'] = count if count
          params['queue'] = queue if queue
          params['type'] = type if type
          params['startTime'] = start_time if start_time
          params['endTime'] = end_time if end_time

          get("/lol/match/v5/matches/by-puuid/#{escape(puuid)}/ids", region, params: params)
        end

        def timeline_by_id(match_id, region: nil)
          get("/lol/match/v5/matches/#{escape(match_id)}/timeline", region)
        end

        def replays(puuid, region: nil)
          Models::Replay.from_api(
            get("/lol/match/v5/matches/by-puuid/#{escape(puuid)}/replays", region)
          )
        end
      end
    end
  end
end
