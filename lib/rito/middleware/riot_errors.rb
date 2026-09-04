# frozen_string_literal: true

module Rito
  module Middleware
    # Raises the mapped Rito::Error for 4xx/5xx responses.
    # Registered below RateLimitObserve so observation happens first.
    class RiotErrors < Faraday::Middleware
      ERROR_CLASSES = {
        400 => Rito::BadRequest,
        401 => Rito::Unauthorized,
        403 => Rito::Forbidden,
        404 => Rito::NotFound,
        405 => Rito::MethodNotAllowed,
        415 => Rito::UnsupportedMediaType
      }.freeze

      def initialize(app, client:)
        super(app)
        @client = client
      end

      def call(env)
        @app.call(env).on_complete { |completed| on_complete(completed) }
      rescue Faraday::RetriableResponse => e
        response = e.response
        raise error_class_for(response.status).new(
          "#{response.status} (after transport retries)",
          response: response
        )
      rescue Faraday::ConnectionFailed => e
        raise Rito::ConnectionError.new("#{e.class}: #{e.message}", wrapped: e)
      rescue Faraday::TimeoutError, Timeout::Error => e
        raise Rito::TimeoutError.new("#{e.class}: #{e.message}", wrapped: e)
      rescue Faraday::SSLError => e
        raise Rito::SSLError.new("#{e.class}: #{e.message}", wrapped: e)
      end

      def on_complete(env)
        return if env.status.between?(200, 299)
        # 5xx are retried by faraday-retry (registered above this middleware);
        # raising here would abort the retry loop on the first attempt.
        return if env.status >= 500

        error_class = error_class_for(env.status)
        return unless error_class

        response = Faraday::Response.new(env)
        if error_class == Rito::RateLimited
          headers = env.response_headers
          raise error_class.new(message(env),
                                retry_after: RateLimiting::HeaderParser.retry_after(headers),
                                limit_type: RateLimiting::HeaderParser.limit_type(headers),
                                response: response)
        end

        raise error_class.new(message(env), response: response)
      end

      private

      def error_class_for(status)
        if status == 429
          Rito::RateLimited
        elsif status.between?(500, 599)
          status == 503 ? Rito::ServiceUnavailable : Rito::ServerError
        else
          ERROR_CLASSES[status]
        end
      end

      def message(env)
        parsed = env.response_body
        parsed = JSON.parse(parsed) if parsed.is_a?(String) && !parsed.empty?
        detail = parsed.is_a?(Hash) ? (parsed['message'] || parsed.dig('status', 'message')) : nil

        base = "#{env.status} #{env.method.to_s.upcase} #{env.url}"
        detail ? "#{base}: #{detail}" : base
      end
    end
  end
end
