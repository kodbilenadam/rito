# frozen_string_literal: true

require 'faraday'
require 'json'

source = 'https://www.mingweisamuel.com/riotapi-schema/openapi-3.0.0.min.json'
response = Faraday.get(source)
raise "Schema download failed (HTTP #{response.status})" unless response.status == 200

schema = JSON.parse(response.body)
operations = schema.fetch('paths').flat_map do |path, methods|
  methods.filter_map do |method, operation|
    next unless %w[get post put delete patch].include?(method)

    query = operation.fetch('parameters', []).filter_map { |param| param['name'] if param['in'] == 'query' }
    { method: method, path: path, regions: operation.fetch('x-platforms-available'), query: query.sort }
  end
end
fixture = { source: source, version: schema.fetch('info').fetch('version'), operations: operations }
File.write(File.expand_path('../test/fixtures/api_routes.json', __dir__), "#{JSON.pretty_generate(fixture)}\n")
puts "Updated #{operations.size} API operations"
