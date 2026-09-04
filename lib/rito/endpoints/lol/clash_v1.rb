# frozen_string_literal: true

module Rito
  module Endpoints
    module Lol
      class ClashV1 < Base
        ROUTING = :platform

        def players_by_summoner_id(summoner_id, region: nil)
          get("/lol/clash/v1/players/by-summoner/#{escape(summoner_id)}", region)
        end

        def team(team_id, region: nil)
          get("/lol/clash/v1/teams/#{escape(team_id)}", region)
        end

        def tournaments(region: nil)
          get('/lol/clash/v1/tournaments', region)
        end

        def tournament_by_team(team_id, region: nil)
          get("/lol/clash/v1/tournaments/by-team/#{escape(team_id)}", region)
        end
      end
    end
  end
end
