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
require 'auth'

SR = 'Serverless Runtime'

# Initialize Provision Engine ruby client
conf_engine = YAML.load_file('/etc/provision-engine/engine.conf')
endpoint = "http://#{conf_engine[:host]}:#{conf_engine[:port]}"
auth = ENV['TESTS_AUTH'] || 'oneadmin:opennebula'
engine_client = ProvisionEngine::Client.new(endpoint, auth)

rspec_conf = {
    :conf => YAML.load_file('./conf.yaml'),
    :engine_client => engine_client,
    :endpoint => endpoint
}

def examples?(examples, conf, params = nil)
    include_context(examples, params) if conf[:examples][examples]
end


# Initialize test configuration
RSpec.configure do |c|
    c.add_setting :rspec
    c.before { @conf = rspec_conf }
end

RSpec.describe 'Provision Engine API' do
    include Rack::Test::Methods

    def wait_delete(sr_id)
        attempts = @conf[:conf][:timeouts][:get]
        1.upto(attempts) do |t|
            sleep 1
            expect(t == attempts).to be(false)

            response = @conf[:engine_client].delete(sr_id)
            rc = response.code

            next unless rc == 204

            expect(rc).to eq(204)

            break
        end
    end

    examples?('auth', rspec_conf[:conf])

    # test every serverless runtime template under templates directory
    Dir.entries("#{__dir__}/templates").select do |sr_template|
        # blacklist template from tests by changing preffix or suffix
        next unless sr_template.start_with?('sr_') && sr_template.end_with?('.json')

        examples?('crud', rspec_conf[:conf], sr_template)
    end

    examples?('inspect logs', rspec_conf[:conf])
end
