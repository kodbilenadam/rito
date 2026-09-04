# frozen_string_literal: true

module Rito
  module Endpoints
    module Tft
      class SummonerV1 < Base
        ROUTING = :platform
        PREFIX = '/tft/summoner/v1/summoners'

        def by_puuid(puuid, region: nil)
          Models::Summoner.from_api(get("#{PREFIX}/by-puuid/#{escape(puuid)}", region))
        end

        # Requires the client to be configured with a bearer_token (RSO).
        def me(region: nil)
          Models::Summoner.from_api(get("#{PREFIX}/me", region))
        end
      end

      class LeagueV1 < Base
        ROUTING = :platform

        def entries_by_puuid(puuid, region: nil)
          get("/tft/league/v1/by-puuid/#{escape(puuid)}", region)
        end

        def entries(tier, division, queue: nil, page: nil, region: nil)
          params = {}
          params['queue'] = queue if queue
          params['page'] = page if page
          get("/tft/league/v1/entries/#{escape(tier)}/#{escape(division)}", region, params: params)
        end

        def challenger(region: nil)
          get('/tft/league/v1/challenger', region)
        end

        def grandmaster(region: nil)
          get('/tft/league/v1/grandmaster', region)
        end

        def master(region: nil)
          get('/tft/league/v1/master', region)
        end

        def rated_ladder_top(queue, region: nil)
          get("/tft/league/v1/rated-ladders/#{escape(queue)}/top", region)
        end
      end

      class MatchV1 < Base
        ROUTING = :regional

        def ids_by_puuid(puuid, count: nil, start: nil, region: nil)
          params = {}
          params['count'] = count if count
          params['start'] = start if start
          get("/tft/match/v1/matches/by-puuid/#{escape(puuid)}/ids", region, params: params)
        end

        def by_id(match_id, region: nil)
          get("/tft/match/v1/matches/#{escape(match_id)}", region)
        end
      end

      class StatusV1 < Base
        ROUTING = :platform

        def platform_data(region: nil)
          get('/tft/status/v1/platform-data', region)
        end
      end

      class SpectatorTftV5 < Base
        ROUTING = :platform

        # Returns nil when the summoner is not in an active game (HTTP 404).
        def active_game(puuid, region: nil)
          get("/lol/spectator/tft/v5/active-games/by-puuid/#{escape(puuid)}", region)
        rescue NotFound
          nil
        end
      end
    end
  end

  module Tft
    class Api
      def initialize(client)
        @client = client
      end

      def summoner
        Endpoints::Tft::SummonerV1.new(@client)
      end

      def leagues
        Endpoints::Tft::LeagueV1.new(@client)
      end

      def matches
        Endpoints::Tft::MatchV1.new(@client)
      end

      def status
        Endpoints::Tft::StatusV1.new(@client)
      end

      def spectator
        Endpoints::Tft::SpectatorTftV5.new(@client)
      end
    end
  end
end
