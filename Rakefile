# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
end

desc 'Record VCR cassettes against the live API'
task :cassettes do
  ruby 'scripts/record_cassettes.rb'
end

desc 'Run rubocop'
task :lint do
  sh 'bundle exec rubocop'
end

task default: :test
