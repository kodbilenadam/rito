# frozen_string_literal: true

module Rito
  module Endpoints
    module Lol
      class LeagueV4 < Base
        ROUTING = :platform

        def challenger(queue, region: nil)
          Models::LeagueList.from_api(
            get("/lol/league/v4/challengerleagues/by-queue/#{escape(queue)}", region)
          )
        end

        def grandmaster(queue, region: nil)
          Models::LeagueList.from_api(
            get("/lol/league/v4/grandmasterleagues/by-queue/#{escape(queue)}", region)
          )
        end

        def master(queue, region: nil)
          Models::LeagueList.from_api(
            get("/lol/league/v4/masterleagues/by-queue/#{escape(queue)}", region)
          )
        end

        def entries_by_puuid(puuid, region: nil)
          get("/lol/league/v4/entries/by-puuid/#{escape(puuid)}", region)
            .map { |hash| Models::LeagueEntry.from_api(hash) }
        end

        def entries(queue, tier, division, page: nil, region: nil)
          params = {}
          params['page'] = page if page
          get("/lol/league/v4/entries/#{escape(queue)}/#{escape(tier)}/#{escape(division)}", region, params: params)
            .map { |hash| Models::LeagueEntry.from_api(hash) }
        end
      end

      class LeagueExpV4 < Base
        ROUTING = :platform

        def entries(queue, tier, division, page: nil, region: nil)
          params = {}
          params['page'] = page if page
          get("/lol/league-exp/v4/entries/#{escape(queue)}/#{escape(tier)}/#{escape(division)}", region, params: params)
            .map { |hash| Models::LeagueEntry.from_api(hash) }
        end
      end
    end
  end
end
