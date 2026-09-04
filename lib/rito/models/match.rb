# frozen_string_literal: true

module Rito
  module Models
    Match = Data.define(:metadata, :info, :raw) do
      def match_id
        metadata&.match_id
      end

      def self.from_api(hash)
        new(
          metadata: MatchMetadata.from_api(hash['metadata']),
          info: MatchInfo.from_api(hash['info']),
          raw: hash.freeze
        )
      end
    end

    MatchMetadata = Data.define(:match_id, :participants, :raw) do
      def self.from_api(hash)
        return nil if hash.nil?

        new(
          match_id: hash['matchId'],
          participants: hash['participants'],
          raw: hash.freeze
        )
      end
    end

    MatchInfo = Data.define(:game_creation, :game_duration, :game_end_timestamp,
                            :game_id, :game_mode, :game_start_timestamp, :game_type,
                            :game_version, :map_id, :participants, :queue_id, :raw) do
      def self.from_api(hash)
        return nil if hash.nil?

        new(
          game_creation: hash['gameCreation'],
          game_duration: hash['gameDuration'],
          game_end_timestamp: hash['gameEndTimestamp'],
          game_id: hash['gameId'],
          game_mode: hash['gameMode'],
          game_start_timestamp: hash['gameStartTimestamp'],
          game_type: hash['gameType'],
          game_version: hash['gameVersion'],
          map_id: hash['mapId'],
          participants: hash['participants']&.map { |p| MatchParticipant.from_api(p) },
          queue_id: hash['queueId'],
          raw: hash.freeze
        )
      end
    end

    MatchParticipant = Data.define(:champion_name, :kills, :deaths, :assists,
                                   :puuid, :summoner_name, :team_id, :win, :raw) do
      def self.from_api(hash)
        new(
          champion_name: hash['championName'],
          kills: hash['kills'],
          deaths: hash['deaths'],
          assists: hash['assists'],
          puuid: hash['puuid'],
          summoner_name: hash['summonerName'],
          team_id: hash['teamId'],
          win: hash['win'],
          raw: hash.freeze
        )
      end
    end

    Replay = Data.define(:total, :match_file_urls, :raw) do
      def self.from_api(hash)
        new(
          total: hash['total'],
          match_file_urls: hash['matchFileURLs'],
          raw: hash.freeze
        )
      end
    end
  end
end
