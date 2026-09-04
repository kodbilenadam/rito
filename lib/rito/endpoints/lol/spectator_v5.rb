# frozen_string_literal: true

module Rito
  module Endpoints
    module Lol
      class SpectatorV5 < Base
        ROUTING = :platform

        # Returns nil when the summoner is not in an active game (HTTP 404).
        def active_game(summoner_id, region: nil)
          get("/lol/spectator/v5/active-games/by-summoner-id/#{escape(summoner_id)}", region)
        rescue NotFound
          nil
        end

        def featured_games(region: nil)
          get('/lol/spectator/v5/featured-games', region)
        end
      end
    end
  end
end
