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
require_relative '../src/client/client'
require_relative '../src/server/runtime'

$LOAD_PATH << "#{__dir__}/lib" # Test libraries
require 'log'
require 'crud'
require 'auth'
require 'crud_invalid'

SR = 'Serverless Runtime'

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
    :conf => YAML.load_file('./conf.yaml'),
    :client => {
        :engine => ProvisionEngine::Client.new(endpoint, auth),
        :oned => OpenNebula::Client.new(auth, conf_engine[:one_xmlrpc]),
        :oneflow => Service::Client.new(flow_client_args)
    },
    :endpoint => endpoint
}

RSpec.configure do |c|
    c.add_setting :rspec
    c.before { @conf = rspec_conf }
end

############################################################################
# RSPEC methods
############################################################################

def examples?(examples, conf, params = nil)
    include_context(examples, params) if conf[:examples][examples]
end

############################################################################
# Run tests
############################################################################
RSpec.describe 'Provision Engine API' do
    include Rack::Test::Methods

    examples?('auth', rspec_conf[:conf])
    examples?('crud_invalid', rspec_conf[:conf])

    # test every serverless runtime template under templates directory
    Dir.entries("#{__dir__}/templates").select do |sr_template|
        # blacklist template from tests by changing preffix or suffix
        next unless sr_template.start_with?('sr_') && sr_template.end_with?('.json')

        examples?('crud', rspec_conf[:conf], sr_template)
    end

    examples?('inspect logs', rspec_conf[:conf])
end

############################################################################
# Helpers
############################################################################

def random_string
    chars = ('a'..'z').to_a + ('A'..'Z').to_a
    string = ''
    8.times { string << chars[SecureRandom.rand(chars.size)] }
    string
end

def random_faas_minimal
    flavour = random_string
    pp "rolled a random flavour #{flavour}"

    {
        :SERVERLESS_RUNTIME => {
            :NAME => flavour,
            :FAAS => {
                :FLAVOUR => flavour
            },
            :SCHEDULING => {},
            :DEVICE_INFO => {}
        }
    }
end
