# frozen_string_literal: true

module Rito
  module Endpoints
    module Lol
      class TournamentV5 < Base
        ROUTING = :platform
        PREFIX = '/lol/tournament/v5'

        def code(tournament_code, region: nil)
          get("#{PREFIX}/codes/by-code/#{escape(tournament_code)}", region)
        end

        def create_codes(tournament_id:, count: nil, body: {}, region: nil)
          params = { 'tournamentId' => tournament_id }
          params['count'] = count if count
          post("#{PREFIX}/codes", region, params: params, body: body)
        end

        def update_code(tournament_code, body: {}, region: nil)
          put("#{PREFIX}/codes/by-code/#{escape(tournament_code)}", region, body: body)
        end

        def lobby_events(tournament_code, region: nil)
          get("#{PREFIX}/lobby-events/by-code/#{escape(tournament_code)}", region)
        end

        def create_provider(body:, region: nil)
          post("#{PREFIX}/providers", region, body: body)
        end

        def create_tournament(body:, region: nil)
          post("#{PREFIX}/tournaments", region, body: body)
        end
      end

      class TournamentStubV5 < Base
        ROUTING = :platform
        PREFIX = '/lol/tournament-stub/v5'

        def code(tournament_code, region: nil)
          get("#{PREFIX}/codes/by-code/#{escape(tournament_code)}", region)
        end

        def create_codes(tournament_id:, count: nil, body: {}, region: nil)
          params = { 'tournamentId' => tournament_id }
          params['count'] = count if count
          post("#{PREFIX}/codes", region, params: params, body: body)
        end

        def update_code(tournament_code, body: {}, region: nil)
          put("#{PREFIX}/codes/by-code/#{escape(tournament_code)}", region, body: body)
        end

        def lobby_events(tournament_code, region: nil)
          get("#{PREFIX}/lobby-events/by-code/#{escape(tournament_code)}", region)
        end

        def create_provider(body:, region: nil)
          post("#{PREFIX}/providers", region, body: body)
        end

        def create_tournament(body:, region: nil)
          post("#{PREFIX}/tournaments", region, body: body)
        end
      end
    end
  end
end
