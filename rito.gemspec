# frozen_string_literal: true

require_relative 'lib/rito/version'

Gem::Specification.new do |spec|
  spec.name = 'rito'
  spec.version = Rito::VERSION
  spec.authors = ['kodbilenadam']
  spec.summary = 'A modern, production-ready Ruby client for the Riot Games API.'
  spec.description = 'Full-coverage Ruby client for the Riot Games API (League of Legends, TFT, ' \
                     'VALORANT, Legends of Runeterra, Riot Account) with adaptive rate limiting.'
  spec.homepage = 'https://github.com/kodbilenadam/rito'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*', 'LICENSE', 'README.md', 'CHANGELOG.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'faraday', '~> 2.13'
  spec.add_dependency 'faraday-retry', '~> 2.2'
end
