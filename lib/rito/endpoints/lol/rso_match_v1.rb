# frozen_string_literal: true

module Rito
  module Endpoints
    module Lol
      # Requires the client to be configured with a bearer_token (RSO) instead
      # of an API key. The player is identified by the token itself; payload
      # shapes are the same as match-v5.
      class RsoMatchV1 < Base
        ROUTING = :regional

        def ids(region: nil, start: nil, count: nil, queue: nil,
                type: nil, start_time: nil, end_time: nil)
          params = {}
          params['start'] = start if start
          params['count'] = count if count
          params['queue'] = queue if queue
          params['type'] = type if type
          params['startTime'] = start_time if start_time
          params['endTime'] = end_time if end_time

          get('/lol/rso-match/v1/matches/ids', region, params: params)
        end

        def by_id(match_id, region: nil)
          Models::Match.from_api(
            get("/lol/rso-match/v1/matches/#{escape(match_id)}", region)
          )
        end

        def timeline_by_id(match_id, region: nil)
          get("/lol/rso-match/v1/matches/#{escape(match_id)}/timeline", region)
        end
      end
    end
  end
end
