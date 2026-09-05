# frozen_string_literal: true

module Rito
  module Endpoints
    class Base
      def initialize(client)
        @client = client
      end

      private

      def get(path, region = nil, params: {})
        @client.request(:get, path, routing_kind: routing_kind, routing_value: region, regions: regions,
                                    params: params).body
      end

      def post(path, region = nil, params: {}, body: nil)
        @client.request(:post, path, routing_kind: routing_kind, routing_value: region, regions: regions,
                                     params: params, body: body).body
      end

      def put(path, region = nil, params: {}, body: nil)
        @client.request(:put, path, routing_kind: routing_kind, routing_value: region, regions: regions,
                                    params: params, body: body).body
      end

      def regions
        self.class::REGIONS if self.class.const_defined?(:REGIONS)
      end

      def routing_kind
        self.class::ROUTING
      end

      def escape(segment)
        ERB::Util.url_encode(segment.to_s)
      end
    end
  end
end
