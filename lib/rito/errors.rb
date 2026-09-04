# frozen_string_literal: true

module Rito
  class Error < StandardError
    attr_reader :response, :status

    def initialize(message = nil, response: nil)
      @response = response
      @status = response&.status
      super(message || default_message)
    end

    private

    def default_message
      base = self.class.name.split('::').last
      detail = @status ? " (HTTP #{@status})" : ''
      "#{base}#{detail}"
    end
  end

  class ConfigError < Error; end

  class BadRequest < Error; end
  class Unauthorized < Error; end
  class Forbidden < Error; end
  class NotFound < Error; end
  class MethodNotAllowed < Error; end
  class UnsupportedMediaType < Error; end

  class RateLimited < Error
    attr_reader :retry_after, :limit_type

    def initialize(message = nil, retry_after: nil, limit_type: nil, response: nil)
      @retry_after = retry_after
      @limit_type = limit_type
      super(message, response: response)
    end
  end

  class ServerError < Error; end
  class ServiceUnavailable < ServerError; end

  class ConnectionError < Error
    attr_reader :wrapped

    def initialize(message = nil, wrapped: nil)
      @wrapped = wrapped
      super(message)
    end
  end

  class TimeoutError < ConnectionError; end
  class SSLError < ConnectionError; end
end
