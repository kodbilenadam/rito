# frozen_string_literal: true

module Rito
  module Models
    Account = Data.define(:puuid, :game_name, :tag_line, :raw) do
      def self.from_api(hash)
        new(
          puuid: hash['puuid'],
          game_name: hash['gameName'],
          tag_line: hash['tagLine'],
          raw: hash.freeze
        )
      end
    end

    ActiveShard = Data.define(:puuid, :game, :active_shard, :raw) do
      def self.from_api(hash)
        new(
          puuid: hash['puuid'],
          game: hash['game'],
          active_shard: hash['activeShard'],
          raw: hash.freeze
        )
      end
    end

    AccountRegion = Data.define(:puuid, :game, :region, :raw) do
      def self.from_api(hash)
        new(
          puuid: hash['puuid'],
          game: hash['game'],
          region: hash['region'],
          raw: hash.freeze
        )
      end
    end
  end
end
