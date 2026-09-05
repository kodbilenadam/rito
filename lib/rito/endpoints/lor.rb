# frozen_string_literal: true

module Rito
  module Endpoints
    module Lor
      class MatchV1 < Base
        ROUTING = :regional

        def ids_by_puuid(puuid, region: nil)
          get("/lor/match/v1/matches/by-puuid/#{escape(puuid)}/ids", region)
        end

        def by_id(match_id, region: nil)
          get("/lor/match/v1/matches/#{escape(match_id)}", region)
        end
      end

      class RankedV1 < Base
        ROUTING = :regional

        def leaderboards(region: nil)
          get('/lor/ranked/v1/leaderboards', region)
        end
      end

      class StatusV1 < Base
        ROUTING = :regional

        def platform_data(region: nil)
          get('/lor/status/v1/platform-data', region)
        end
      end

      class DeckV1 < Base
        ROUTING = :regional

        # Requires the client to be configured with a bearer_token (RSO).
        def my_decks(region: nil)
          get('/lor/deck/v1/decks/me', region)
        end

        # Requires the client to be configured with a bearer_token (RSO).
        def create_deck(body:, region: nil)
          post('/lor/deck/v1/decks/me', region, body: body)
        end
      end

      class InventoryV1 < Base
        ROUTING = :regional

        # Requires the client to be configured with a bearer_token (RSO).
        def my_cards(region: nil)
          get('/lor/inventory/v1/cards/me', region)
        end
      end
    end
  end

  module Lor
    class Api
      def initialize(client)
        @client = client
      end

      def matches
        Endpoints::Lor::MatchV1.new(@client)
      end

      def ranked
        Endpoints::Lor::RankedV1.new(@client)
      end

      def status
        Endpoints::Lor::StatusV1.new(@client)
      end

      def decks
        Endpoints::Lor::DeckV1.new(@client)
      end

      def inventory
        Endpoints::Lor::InventoryV1.new(@client)
      end
    end
  end
end
