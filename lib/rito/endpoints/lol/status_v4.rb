# frozen_string_literal: true

module Rito
  module Endpoints
    module Lol
      class StatusV4 < Base
        ROUTING = :platform

        def platform_data(region: nil)
          get('/lol/status/v4/platform-data', region)
        end
      end
    end
  end
end
