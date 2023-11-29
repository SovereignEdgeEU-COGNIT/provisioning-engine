#!/usr/bin/env ruby

# How to use: See .github/workflows/rspec.yml

# Standard library
require 'json'
require 'yaml'
require 'securerandom'

# Gems
require 'rspec'
require 'rack/test'
require 'json-schema'
require 'opennebula'
require 'opennebula/oneflow_client'

# Engine libraries
$LOAD_PATH << "#{__dir__}/../src/server"
require 'runtime'
require 'function'
require 'error'
require_relative '../src/client/client'

$LOAD_PATH << "#{__dir__}/lib" # Test libraries
require 'common'

############################################################################
# Initialize rspec configuration
############################################################################
conf_engine = YAML.load_file('/etc/provision-engine/engine.conf')
endpoint = "http://#{conf_engine[:host]}:#{conf_engine[:port]}"
auth = ENV['TESTS_AUTH'] || 'oneadmin:opennebula'
flow_client_args = {
    :url => conf_engine[:oneflow_server],
    :username => auth.split(':')[0],
    :password => auth.split(':')[-1]
}

rspec_conf = {
    :conf => {
        :tests => YAML.load_file('./conf.yaml'),
        :engine => conf_engine
    },
    :client => {
        :engine => ProvisionEngine::Client.new(endpoint, auth),
        :oned => OpenNebula::Client.new(auth, conf_engine[:one_xmlrpc]),
        :oneflow => Service::Client.new(flow_client_args)
    },
    :endpoint => endpoint
}

RSpec.configure {|c| c.before { @conf = rspec_conf } }

############################################################################
# Run tests
############################################################################
RSpec.describe 'Provision Engine API' do
    include Rack::Test::Methods
    tests = rspec_conf[:conf][:tests][:examples]

    if tests['crud']
        require 'crud'

        # test every serverless runtime template under templates directory
        Dir.entries("#{__dir__}/templates").select do |sr_template|
            # blacklist template from tests by changing preffix or suffix
            next unless sr_template.start_with?('sr_') && sr_template.end_with?('.json')

            include_context('crud', sr_template)
        end
    end

    tests.each do |examples, enabled|
        next if examples == 'crud'

        if enabled
            require examples
            include_context(examples)
        end
    end

    after(:all) do
        if rspec_conf[:conf][:tests][:purge]
            require 'client'
            require 'log'
            require 'logger'

            client = ProvisionEngine::CloudClient.new(conf_engine, auth)
            response = client.service_pool_get
            expect(response[0]).to eq(200)

            document_pool = response[1]['DOCUMENT_POOL']
            if !document_pool.empty?
                pp "Found leftover services as the user #{auth.split(':')[0]}"

                document_pool['DOCUMENT'].each do |service|
                    pp "#{service['ID']}: #{service['NAME']}"

                    response = client.service_destroy(service['ID'])
                    expect([204, 404].include?(response[0])).to be(true)
                end
            end
        end
    end
end
