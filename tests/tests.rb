#!/usr/bin/env ruby

# How to use: See ./github/workflows/rspec.yml

require 'json'
require 'yaml'
require 'rspec'
require 'rack/test'

# Serverless Runtime libary requirements
require 'opennebula'
require 'json-schema'

require_relative '../src/client/client'
require_relative '../src/server/runtime'

SR = 'Serverless Runtime'

conf_engine = YAML.load_file('/etc/provision-engine/engine.conf')
endpoint = "http://#{conf_engine[:host]}:#{conf_engine[:port]}"

conf_tests = YAML.load_file('./conf.yaml')
auth = ENV['TESTS_AUTH'] || 'oneadmin:opennebula'

engine_client = ProvisionEngine::Client.new(endpoint, auth)

id = nil

describe 'Provision Engine API' do
    include Rack::Test::Methods

    it "should create a #{SR} with a minimal specification" do
        file_path = 'example_runtime_definition_minimal.json'
        specification = File.read(file_path)
        specification = JSON.parse(specification)

        response = engine_client.create(specification)

        expect(response.code.to_i).to eq(201)

        runtime = JSON.parse(response.body)
        pp runtime

        id = runtime['SERVERLESS_RUNTIME']['ID'].to_i

        validation = ProvisionEngine::ServerlessRuntime.validate(runtime)
        pp validation[1]

        expect(validation[0]).to be(true)
    end

    it "should get #{SR} info" do
        attempts = conf_tests[:timeouts][:get]

        1.upto(attempts) do |t|
            sleep 1
            expect(t == attempts).to be(false)

            response = engine_client.get(id)

            expect(response.code.to_i).to eq(200)

            runtime = JSON.parse(response.body)
            pp runtime

            # Even though the VM reaches RUNNING, the service might not
            next unless runtime['SERVERLESS_RUNTIME']['FAAS']['STATE'] == 'ACTIVE'

            break
        end
    end

    it "should get #{SR} update not implemented" do
        response = engine_client.update(id, {})

        expect(response.code.to_i).to eq(501)

        body = JSON.parse(response.body)
        pp body

        expect(body).to eq('Serverless Runtime update not implemented')
    end

    it "should delete a #{SR}" do
        attempts = conf_tests[:timeouts][:get]

        1.upto(attempts) do |t|
            sleep 1
            expect(t == attempts).to be(false)

            response = engine_client.delete(id)
            rc = response.code.to_i

            next unless rc == 204

            expect(rc).to eq(204)

            break
        end
    end

    it 'prints every log' do
        logcation = '/var/log/provision-engine'

        pp '-----------------------------------'
        pp File.read("#{logcation}/engine.log")
        pp '-----------------------------------'
        pp File.read("#{logcation}/api.log")
        pp '-----------------------------------'
    end
end
