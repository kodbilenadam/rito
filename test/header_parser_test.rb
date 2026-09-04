# frozen_string_literal: true

require_relative 'test_helper'

class HeaderParserTest < Minitest::Test
  HEADERS = {
    'X-App-Rate-Limit' => '20:1,100:120',
    'X-App-Rate-Limit-Count' => '5:1,42:120',
    'X-Method-Rate-Limit' => '2000:10',
    'X-Method-Rate-Limit-Count' => '137:10',
    'Retry-After' => '30',
    'X-Rate-Limit-Type' => 'application'
  }.freeze

  def test_app_limits
    assert_equal [[20, 1], [100, 120]], Rito::RateLimiting::HeaderParser.app_limits(HEADERS)
  end

  def test_app_counts
    assert_equal [[5, 1], [42, 120]], Rito::RateLimiting::HeaderParser.app_counts(HEADERS)
  end

  def test_method_limits
    assert_equal [[2000, 10]], Rito::RateLimiting::HeaderParser.method_limits(HEADERS)
  end

  def test_method_counts
    assert_equal [[137, 10]], Rito::RateLimiting::HeaderParser.method_counts(HEADERS)
  end

  def test_missing_headers_return_empty
    assert_empty Rito::RateLimiting::HeaderParser.app_limits({})
    assert_empty Rito::RateLimiting::HeaderParser.method_counts({})
  end

  def test_retry_after
    assert_equal 30, Rito::RateLimiting::HeaderParser.retry_after(HEADERS)
    assert_nil Rito::RateLimiting::HeaderParser.retry_after({})
    assert_nil Rito::RateLimiting::HeaderParser.retry_after({ 'Retry-After' => 'Wed, 21 Oct 2026 07:28:00 GMT' })
  end

  def test_limit_type
    assert_equal :application, Rito::RateLimiting::HeaderParser.limit_type(HEADERS)
    assert_equal :method, Rito::RateLimiting::HeaderParser.limit_type({ 'X-Rate-Limit-Type' => 'method' })
    assert_equal :service, Rito::RateLimiting::HeaderParser.limit_type({ 'X-Rate-Limit-Type' => 'service' })
    assert_nil Rito::RateLimiting::HeaderParser.limit_type({})
  end

  def test_malformed_values_are_ignored
    headers = { 'X-App-Rate-Limit' => '20:1, oops, 100:120' }
    assert_equal [[20, 1], [100, 120]], Rito::RateLimiting::HeaderParser.app_limits(headers)
  end
end
