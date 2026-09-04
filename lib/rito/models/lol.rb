# frozen_string_literal: true

module Rito
  module Models
    ChampionMastery = Data.define(
      :puuid, :champion_id, :champion_level, :champion_points,
      :champion_points_until_next_level, :champion_points_since_last_level,
      :last_play_time, :tokens_earned, :raw
    ) do
      def self.from_api(hash)
        new(
          puuid: hash['puuid'],
          champion_id: hash['championId'],
          champion_level: hash['championLevel'],
          champion_points: hash['championPoints'],
          champion_points_until_next_level: hash['championPointsUntilNextLevel'],
          champion_points_since_last_level: hash['championPointsSinceLastLevel'],
          last_play_time: hash['lastPlayTime'],
          tokens_earned: hash['tokensEarned'],
          raw: hash.freeze
        )
      end
    end

    ChampionInfo = Data.define(:sr, :newplayer, :raw) do
      def self.from_api(hash)
        new(
          sr: hash['sr'],
          newplayer: hash['newplayer'],
          raw: hash.freeze
        )
      end
    end

    LeagueEntry = Data.define(
      :puuid, :summoner_id, :queue_type, :tier, :rank, :league_id,
      :league_points, :wins, :losses, :veteran, :fresh_blood, :hot_streak,
      :inactive, :raw
    ) do
      def self.from_api(hash)
        new(
          puuid: hash['puuid'],
          summoner_id: hash['summonerId'],
          queue_type: hash['queueType'],
          tier: hash['tier'],
          rank: hash['rank'],
          league_id: hash['leagueId'],
          league_points: hash['leaguePoints'],
          wins: hash['wins'],
          losses: hash['losses'],
          veteran: hash['veteran'],
          fresh_blood: hash['freshBlood'],
          hot_streak: hash['hotStreak'],
          inactive: hash['inactive'],
          raw: hash.freeze
        )
      end

      def winrate
        total = wins.to_i + losses.to_i
        return nil if total.zero?

        (wins.to_f / total * 100).round(2)
      end
    end

    LeagueList = Data.define(:league_id, :tier, :name, :queue, :entries, :raw) do
      def self.from_api(hash)
        new(
          league_id: hash['leagueId'],
          tier: hash['tier'],
          name: hash['name'],
          queue: hash['queue'],
          entries: hash['entries'].to_a.freeze,
          raw: hash.freeze
        )
      end
    end
  end
end
