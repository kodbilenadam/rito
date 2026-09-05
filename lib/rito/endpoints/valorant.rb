# frozen_string_literal: true

module Rito
  module Endpoints
    module Valorant
      class ContentV1 < Base
        ROUTING = :valorant_platform

        def contents(locale: nil, region: nil)
          params = {}
          params['locale'] = locale if locale
          get('/val/content/v1/contents', region, params: params)
        end
      end

      class MatchV1 < Base
        ROUTING = :valorant_platform

        def by_id(match_id, region: nil)
          get("/val/match/v1/matches/#{escape(match_id)}", region)
        end

        def ids_by_puuid(puuid, region: nil)
          get("/val/match/v1/matchlists/by-puuid/#{escape(puuid)}", region)
        end

        def recent_by_queue(queue, region: nil)
          get("/val/match/v1/recent-matches/by-queue/#{escape(queue)}", region)
        end
      end

      class ConsoleMatchV1 < Base
        ROUTING = :valorant_console_platform

        def by_id(match_id, region: nil)
          get("/val/match/console/v1/matches/#{escape(match_id)}", region)
        end

        def ids_by_puuid(puuid, platform_type:, region: nil)
          get("/val/match/console/v1/matchlists/by-puuid/#{escape(puuid)}", region,
              params: { 'platformType' => platform_type })
        end

        def recent_by_queue(queue, region: nil)
          get("/val/match/console/v1/recent-matches/by-queue/#{escape(queue)}", region)
        end
      end

      class RankedV1 < Base
        ROUTING = :valorant_platform

        def leaderboard(act_id, size: nil, start_index: nil, region: nil)
          params = {}
          params['size'] = size if size
          params['startIndex'] = start_index if start_index
          get("/val/ranked/v1/leaderboards/by-act/#{escape(act_id)}", region, params: params)
        end
      end

      class ConsoleRankedV1 < Base
        ROUTING = :valorant_console_platform

        def leaderboard(act_id, platform_type:, size: nil, start_index: nil, region: nil)
          params = { 'platformType' => platform_type }
          params['size'] = size if size
          params['startIndex'] = start_index if start_index
          get("/val/console/ranked/v1/leaderboards/by-act/#{escape(act_id)}", region, params: params)
        end
      end

      class StatusV1 < Base
        ROUTING = :valorant_platform

        def platform_data(region: nil)
          get('/val/status/v1/platform-data', region)
        end
      end
    end
  end

  module Val
    class Api
      def initialize(client)
        @client = client
      end

      def content
        Endpoints::Valorant::ContentV1.new(@client)
      end

      def matches
        Endpoints::Valorant::MatchV1.new(@client)
      end

      def console_matches
        Endpoints::Valorant::ConsoleMatchV1.new(@client)
      end

      def console_ranked
        Endpoints::Valorant::ConsoleRankedV1.new(@client)
      end

      def ranked
        Endpoints::Valorant::RankedV1.new(@client)
      end

      def status
        Endpoints::Valorant::StatusV1.new(@client)
      end
    end
  end
end
