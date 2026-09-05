# frozen_string_literal: true

module Rito
  module Models
    def self.deep_freeze(value)
      case value
      when Hash
        value.each do |key, item|
          deep_freeze(key)
          deep_freeze(item)
        end
      when Array
        value.each { |item| deep_freeze(item) }
      end
      value.freeze
    end
  end
end
