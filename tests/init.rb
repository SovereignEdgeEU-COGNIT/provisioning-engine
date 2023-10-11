#!/usr/bin/env ruby

# How to use: See .github/workflows/rspec.yml

# Standard library
require 'json'
require 'yaml'

# Gems
require 'rspec'
require 'rack/test'

# Engine libraries
require 'opennebula'
require 'json-schema'
require_relative '../src/client/client'
require_relative '../src/server/runtime'

$LOAD_PATH << "#{__dir__}/lib"
require 'log'
require 'crud'

SR = 'Serverless Runtime'

# Initialize Provision Engine ruby client
conf_engine = YAML.load_file('/etc/provision-engine/engine.conf')
endpoint = "http://#{conf_engine[:host]}:#{conf_engine[:port]}"
auth = ENV['TESTS_AUTH'] || 'oneadmin:opennebula'
engine_client = ProvisionEngine::Client.new(endpoint, auth)

# Initialize test configuration
rspec = {
    :conf => YAML.load_file('./conf.yaml'),
    :engine_client => engine_client,
    :sr_templates => []
}

describe 'Provision Engine API' do
    include Rack::Test::Methods

    let(:rspec) { rspec }

    # test every serverless runtime template available under template directory
    Dir.entries("#{__dir__}/templates").select do |sr_template|
        # blacklist template from tests by changing preffix or suffix
        next unless sr_template.start_with?('sr_') && sr_template.end_with?('.json')

        include_context('crud', sr_template)
    end

    include_context('inspect logs')
end
