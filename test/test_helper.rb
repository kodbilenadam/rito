# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/pride'
require 'rito'
require 'webmock/minitest'
require 'vcr'

WebMock.disable_net_connect!

VCR.configure do |config|
  config.cassette_library_dir = 'test/vcr_cassettes'
  config.hook_into :webmock
  config.default_cassette_options = { record: :once }
  config.filter_sensitive_data('<RIOT_API_KEY>') { ENV['RIOT_API_KEY_TEST'] } if ENV['RIOT_API_KEY_TEST']
end

module Rito
  module TestHelpers
    def with_config(**options)
      originals = {
        api_key: Rito.api_key,
        bearer_token: Rito.bearer_token,
        region: Rito.region,
        rate_limiter: Rito.rate_limiter,
        max_retries: Rito.max_retries
      }
      options.each { |key, value| Rito.public_send("#{key}=", value) }
      yield
    ensure
      originals.each { |key, value| Rito.public_send("#{key}=", value) }
    end
  end
end

module Minitest
  class Test
    include Rito::TestHelpers
  end
end
