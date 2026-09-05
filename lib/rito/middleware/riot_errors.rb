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

      FORBIDDEN_HINT = ' (check routing, product access, and the API key: dev keys expire every 24h)'

      def initialize(app, client:)
        super(app)
        @client = client
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

      def parse_body(body)
        body = JSON.parse(body) if body.is_a?(String) && !body.empty?
        body.is_a?(Hash) ? body : {}
      rescue JSON::ParserError
        {}
      end

      def message(env)
        parsed = parse_body(env.response_body)
        status = parsed['status']
        detail = parsed['message'] || (status['message'] if status.is_a?(Hash))

        base = "#{env.status} #{env.method.to_s.upcase} #{env.url}"
        text = detail ? "#{base}: #{detail}" : base
        text += FORBIDDEN_HINT if env.status == 403
        text
      end
    end
  end
end
