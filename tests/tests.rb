#!/usr/bin/env ruby

# How to use
# set the engine client authentication and engine endpoint at ./conf.yaml
# ./prepare.sh $oned $oneflow $nature $nature-s3 && provision-engine-server start && rspec tests.rb

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

conf = YAML.load_file('./conf.yaml')
endpoint = conf[:engine_endpoint] || 'http://localhost:1337/'
auth = conf[:auth] || 'oneadmin:opennebula'

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

        document = JSON.parse(response.body)
        pp document

        id = document['DOCUMENT']['ID'].to_i
        body = runtime_body(document)

        validation = ProvisionEngine::ServerlessRuntime.validate(body)
        pp validation[1]

        expect(validation[0]).to be(true)
    end

    it "should get #{SR} info" do
        attempts = 30

        1.upto(attempts) do |t|
            expect(t == attempts).to be(false)

            response = engine_client.get(id)

            expect(response.code.to_i).to eq(200)

            document = JSON.parse(response.body)
            pp document

            body = runtime_body(document)

            # Even though the VM reaches RUNNING, the service might not
            next unless body['FAAS']['STATE'] == 'ACTIVE'

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
        attempts = 10

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
end

def runtime_body(document)
    document['DOCUMENT']['TEMPLATE']['BODY']
end
