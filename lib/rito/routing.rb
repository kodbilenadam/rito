# frozen_string_literal: true

module Rito
  module Routing
    PLATFORMS = %w[
      br1 eun1 euw1 jp1 kr la1 la2 me1 na1 oc1 ph2 ru sg2 th2 tr1 tw2 vn2
    ].freeze
    REGIONALS = %w[americas asia europe sea].freeze

    CLUSTERS = {
      'americas' => %w[na1 br1 la1 la2],
      'europe' => %w[euw1 eun1 tr1 ru me1],
      'asia' => %w[kr jp1],
      'sea' => %w[oc1 sg2 tw2 vn2 ph2 th2]
    }.freeze

    ACCOUNT_REGIONALS = %w[americas asia europe].freeze

    VALORANT_PLATFORMS = %w[na1 eu ap kr latam br].freeze
    VALORANT_CONSOLE_PLATFORMS = %w[na eu ap].freeze

    class << self
      def platform?(value)
        PLATFORMS.include?(normalize(value))
      end

      def regional?(value)
        REGIONALS.include?(normalize(value))
      end

      def normalize(value)
        value.to_s.downcase
      end

      def host_for(value)
        v = normalize(value)
        case v
        when *PLATFORMS, *REGIONALS, *VALORANT_PLATFORMS, *VALORANT_CONSOLE_PLATFORMS
          "#{v}.api.riotgames.com"
        else
          raise ArgumentError, "unknown routing value: #{value.inspect}"
        end
      end

      def resolve(routing_kind, value)
        v = normalize(value)
        case routing_kind
        when :valorant_platform
          return v if VALORANT_PLATFORMS.include?(v)

          raise ArgumentError, "#{value.inspect} is not usable as a VALORANT platform routing value"
        when :valorant_console_platform
          return v if VALORANT_CONSOLE_PLATFORMS.include?(v)

          raise ArgumentError, "#{value.inspect} is not usable as a VALORANT console platform routing value"
        end

        return v if routing_kind == :platform && platform?(v)
        return v if routing_kind == :regional && regional?(v)

        if routing_kind == :regional && platform?(v)
          CLUSTERS.each do |regional, platforms|
            return regional if platforms.include?(v)
          end
        end

        raise ArgumentError, "#{value.inspect} is not usable as a #{routing_kind} routing value"
      end

      def regional_for_account(value)
        v = normalize(value)
        return v if ACCOUNT_REGIONALS.include?(v)
        return 'asia' if v == 'sea'

        resolve(:regional, v)
      end
    end
  end
end
