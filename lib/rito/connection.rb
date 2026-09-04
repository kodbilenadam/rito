# frozen_string_literal: true

module Rito
  class Connection
    def initialize(client)
      @client = client
      @connections = {}
      @mutex = Mutex.new
    end

    def for_host(host)
      @mutex.synchronize do
        @connections[host] ||= build(host)
      end
    end

    private

    def build(host)
      Faraday.new("https://#{host}") do |f|
        f.options.open_timeout = @client.open_timeout
        f.options.timeout = @client.timeout
        f.request :json
        f.request :retry,
                  max: @client.max_retries,
                  retry_statuses: [500, 503, 504],
                  interval: 0.5,
                  backoff_factor: 2,
                  exceptions: [Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::RetriableResponse]
        f.use Middleware::RateLimitThrottle, client: @client
        f.use Middleware::Authentication, client: @client
        f.use Middleware::RiotErrors, client: @client
        f.use Middleware::RateLimitObserve, client: @client
        f.response :json, content_type: /\bjson$/
        f.adapter @client.adapter
      end
    end
  end
end
