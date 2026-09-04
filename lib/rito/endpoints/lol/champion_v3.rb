# frozen_string_literal: true

module Rito
  module Endpoints
    module Lol
      class ChampionV3 < Base
        ROUTING = :platform

        def rotations(region: nil)
          Models::ChampionInfo.from_api(
            get('/lol/platform/v3/champion-rotations', region)
          )
        end
      end
    end
  end
end
