#!/usr/bin/env ruby

# How to use
# set the engine client authentication in the environmental variable ONE_AUTH
# export ONE_AUTH='user:pass'
# ./prepare.sh && rspec tests.rb

require 'rspec'
require 'json'
require 'rack/test'

# Serverless Runtime libary requirements
require 'opennebula'
require 'json-schema'

require_relative '../src/client/client'
require_relative '../src/server/runtime'

SR = 'Serverless Runtime'

endpoint = 'http://localhost:1337/'
auth = ENV['ONE_AUTH'] || 'oneadmin:opennebula'

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
        1.upto(30) do |t|
            expect(t == 30).to be(false)

            response = engine_client.get(id)

            expect(response.code.to_i).to eq(200)

            document = JSON.parse(response.body)
            pp document

            body = runtime_body(document)

            next unless body['FAAS']['STATE'] == 'ACTIVE'

            break
        end
    end

    it "should get #{SR} update not implemented" do
        response = engine_client.update(id, {})

        body = JSON.parse(response.body)
        pp body

        expect(response.code.to_i).to eq(501)
        expect(body).to eq('Serverless Runtime update not implemented')
    end

    it "should delete a #{SR}" do
        response = engine_client.delete(id)

        expect(response.code.to_i).to eq(204)
    end
end

def runtime_body(document)
    document['DOCUMENT']['TEMPLATE']['BODY']
end
