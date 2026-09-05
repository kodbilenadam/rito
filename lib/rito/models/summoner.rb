# frozen_string_literal: true

module Rito
  module Models
    Summoner = Data.define(
      :id, :account_id, :puuid, :name, :profile_icon_id,
      :revision_date, :summoner_level, :raw
    ) do
      def self.from_api(hash)
        new(
          id: hash['id'],
          account_id: hash['accountId'],
          puuid: hash['puuid'],
          name: hash['name'],
          profile_icon_id: hash['profileIconId'],
          revision_date: hash['revisionDate'],
          summoner_level: hash['summonerLevel'],
          raw: Models.deep_freeze(hash)
        )
      end
    end
  end
end
