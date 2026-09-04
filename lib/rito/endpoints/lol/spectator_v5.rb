# frozen_string_literal: true

module Rito
  module Endpoints
    module Lol
      class SpectatorV5 < Base
        ROUTING = :platform

        # Returns nil when the summoner is not in an active game (HTTP 404).
        def active_game(puuid, region: nil)
          get("/lol/spectator/v5/active-games/by-summoner/#{escape(puuid)}", region)
        rescue NotFound
          nil
        end
      end
    end
  end
end
