# frozen_string_literal: true

require_relative 'test_helper'

class ApiContractTest < Minitest::Test
  class CapturedRequest < StandardError
    attr_reader :request

    def initialize(request)
      @request = request
      super('captured request')
    end
  end

  class CaptureClient
    attr_reader :region

    def initialize(region)
      @region = region
    end

    def request(method, path, routing_kind:, routing_value: nil, **options)
      region = Rito::Routing.resolve(routing_kind, routing_value || @region)
      raise CapturedRequest.new({ method: method.to_s, path: path, region: region, **options })
    end
  end

  def test_endpoints_match_published_paths_routing_and_query_parameters
    fixture = JSON.parse(File.read(File.join(__dir__, 'fixtures/api_routes.json')))
    expected = fixture.fetch('operations').to_h do |operation|
      [[operation['method'], normalize(operation['path'])], operation]
    end
    actual = {}
    classes = ObjectSpace.each_object(Class).select { |klass| klass < Rito::Endpoints::Base }
    classes.each do |klass|
      region = klass::ROUTING.to_s.start_with?('valorant') ? :na : :na1
      endpoint = klass.new(CaptureClient.new(region))
      klass.public_instance_methods(false).each do |name|
        method = endpoint.method(name)
        args = method.parameters.select { |kind, _| kind == :req }.map { 'contract/value' }
        kwargs = method.parameters.filter_map do |kind, parameter|
          next unless %i[key keyreq].include?(kind) && parameter != :region

          [parameter, parameter == :body ? {} : 'contract/value']
        end.to_h
        capture = assert_raises(CapturedRequest, "#{klass}##{name}") { method.call(*args, **kwargs) }
        request = capture.request
        key = [request[:method], request[:path].gsub('contract%2Fvalue', '{}')]
        operation = expected[key]
        refute_nil operation, "undocumented path: #{key}"
        next unless operation

        assert_includes operation['regions'], request[:region], "#{klass}##{name} routes incorrectly"
        assert_equal operation['query'], request.fetch(:params, {}).keys.sort, "#{klass}##{name} query parameters"
        refute actual.key?(key), "duplicate operation: #{key}"
        actual[key] = true
      end
    end
    assert_equal expected.keys.sort, actual.keys.sort
  end

  private

  def normalize(path)
    path.gsub(/\{[^}]+\}/, '{}')
  end
end
