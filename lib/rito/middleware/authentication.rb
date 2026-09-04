# frozen_string_literal: true

module Rito
  module Middleware
    class Authentication < Faraday::Middleware
      def initialize(app, client:)
        super(app)
        @client = client
      end

      def call(env)
        if @client.api_key
          env.request_headers['X-Riot-Token'] = @client.api_key
        elsif @client.bearer_token
          env.request_headers['Authorization'] = "Bearer #{@client.bearer_token}"
        end
        @app.call(env)
      end
    end
  end
end
