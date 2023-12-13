#!/usr/bin/env ruby

# Standard library
require 'json'
require 'yaml'
require 'base64'
require 'fileutils'
require 'syslog'
require 'securerandom'

# Gems
require 'sinatra'
require 'logger'
require 'json-schema'
require 'opennebula'
require 'opennebula/oneflow_client'
require 'opennebula/../models/service'

# Engine libraries
$LOAD_PATH << '/opt/provision-engine/' # install dir defined on install.sh
require 'log'
require 'configuration'
require 'client'
require 'error'
require 'runtime'
require 'function'

############################################################################
# API configuration
############################################################################

VERSION = '1.0.1'
conf = ProvisionEngine::Configuration.new

configure do
    set :bind, conf[:host]
    set :port, conf[:port]
    set :logger, ProvisionEngine::Logger.new(conf[:log])
end

settings.logger.info "Using oned at #{conf[:one_xmlrpc]}"
settings.logger.info "Using oneflow at #{conf[:oneflow_server]}"

############################################################################
# Routes setup
############################################################################

# Log every HTTP Request received
before do
    if conf[:log][:level] == 0
        call = "API Call: #{request.request_method} #{request.fullpath} #{request.body.read}"
        settings.logger.debug(call)
        request.body.rewind
    end
end

get '/serverless-runtimes/schema' do
    json_response(200, ProvisionEngine::ServerlessRuntime::SCHEMA)
end

post '/serverless-runtimes' do
    log_request("Create a #{SR}")

    auth = auth?
    specification = body_valid?

    client = ProvisionEngine::CloudClient.new(conf, auth)

    response = ProvisionEngine::ServerlessRuntime.create(client, specification)
    rc = response[0]
    rb = response[1]

    case rc
    when 201
        log_response('info', rc, rb, "#{SR} created")
        json_response(rc, rb.to_sr)
    when 400
        log_response('error', rc, rb, "Invalid #{SRD}")
        halt rc, json_response(rc, rb)
    when 401
        log_response('error', rc, rb, NO_AUTH)
        halt rc, json_response(rc, rb)
    when 403
        log_response('error', rc, rb, DENIED)
        halt rc, json_response(rc, rb)
    when 422
        log_response('error', rc, rb, "Unprocessable #{SRD}")
        halt rc, json_response(rc, rb)
    when 504
        log_response('error', rc, rb, "Timeout when creating #{SR}")
        halt rc, json_response(rc, rb)
    else
        log_response('error', 500, rb, "Failed to create #{SR}")
        halt 500, json_response(500, rb)
    end
end

get '/serverless-runtimes/:id' do
    log_request("Retrieve a #{SR} information")

    auth = auth?

    client = ProvisionEngine::CloudClient.new(conf, auth)
    id = params[:id].to_i

    response = ProvisionEngine::ServerlessRuntime.get(client, id)
    rc = response[0]
    rb = response[1]

    case rc
    when 200
        document = rb

        log_response('info', rc, document, "#{SR} retrieved")
        json_response(rc, document.to_sr)
    when 401
        log_response('error', rc, rb, NO_AUTH)
        halt rc, json_response(rc, rb)
    when 403
        log_response('error', rc, rb, DENIED)
        halt rc, json_response(rc, rb)
    when 404
        log_response('error', rc, rb, SR_NOT_FOUND)
        halt rc, json_response(rc, rb)
    else
        log_response('error', 500, rb, "Failed to retrieve #{SR}")
        halt 500, json_response(500, rb)
    end
end

put '/serverless-runtimes/:id' do
    log_request("Update a #{SR}")

    auth = auth?
    specification = body_valid?

    client = ProvisionEngine::CloudClient.new(conf, auth)
    id = params[:id].to_i

    response = ProvisionEngine::ServerlessRuntime.get(client, id)
    rc = response[0]
    rb = response[1]

    case rc
    when 200
        document = rb

        response = document.update_sr(specification)
        rc = response[0]
        rb = response[1]

        case rc
        when 200
            log_response('info', rc, rb, "#{SR} updated")
            json_response(rc, document.to_sr)
        when 403
            log_response('error', rc, rb, DENIED)
            halt rc, json_response(rc, rb)
        when 423
            log_response('error', rc, rb, NO_UPDATE)
            halt rc, json_response(rc, rb)
        else
            log_response('error', 500, rb, NO_UPDATE)
            halt 500, json_response(500, rb)
        end
    when 401
        log_response('error', rc, rb, NO_AUTH)
        halt rc, json_response(rc, rb)
    when 403
        log_response('error', rc, rb, DENIED)
        halt rc, json_response(rc, rb)
    when 404
        log_response('error', rc, rb, SR_NOT_FOUND)
        halt rc, json_response(rc, rb)
    else
        log_response('error', 500, rb, NO_UPDATE)
        halt 500, json_response(500, rb)
    end
end

delete '/serverless-runtimes/:id' do
    log_request("Delete a #{SR}")

    auth = auth?

    client = ProvisionEngine::CloudClient.new(conf, auth)
    id = params[:id].to_i

    response = ProvisionEngine::ServerlessRuntime.get(client, id)
    rc = response[0]
    rb = response[1]

    case rc
    when 200
        runtime = rb

        response = runtime.delete
        rc = response[0]
        rb = response[1]

        case rc
        when 204
            log_response('info', rc, rb, "#{SR} deleted")
            json_response(rc, rb)
        when 403
            log_response('error', rc, rb, DENIED)
            halt rc, json_response(rc, rb)
        when 423
            log_response('error', rc, rb, NO_DELETE)
            halt rc, json_response(rc, rb)
        else
            log_response('error', 500, rb, NO_DELETE)
            halt 500, json_response(500, rb)
        end
    when 401
        log_response('error', rc, rb, NO_AUTH)
        halt rc, json_response(rc, rb)
    when 403
        log_response('error', rc, rb, DENIED)
        halt rc, json_response(rc, rb)
    when 404
        log_response('error', rc, rb, SR_NOT_FOUND)
        halt rc, json_response(rc, rb)
    else
        log_response('error', 500, rb, NO_DELETE)
        halt 500, json_response(500, rb)
    end
end

get '/server/version' do
    json_response(200, VERSION)
end

get '/server/config' do
    json_response(200, conf)
end

############################################################################
# Define API Helpers
############################################################################
RC = 'Response HTTP Return Code'.freeze
PE = 'Provisioning Engine'.freeze
SR = 'Serverless Runtime'.freeze
DENIED = 'Permission denied'.freeze
NO_AUTH = 'Failed to authenticate in OpenNebula'.freeze
SRD = "#{SR} definition".freeze
SR_NOT_FOUND = "#{SR} not found".freeze
NO_DELETE = "Failed to delete #{SR}".freeze
NO_UPDATE = "Failed to update #{SR}".freeze

# Helper method to return JSON responses
def json_response(response_code, data)
    content_type :json
    status response_code
    data.to_json
end

def auth?
    auth_header = request.env['HTTP_AUTHORIZATION']

    if auth_header.nil?
        rc = 401
        error = 'Authentication required'

        settings.logger.error(error)
        halt rc, json_response(rc, ProvisionEngine::Error.new(rc, error))
    end

    if auth_header.start_with?('Basic ')
        encoded_credentials = auth_header.split(' ')[1]
        username, password = Base64.decode64(encoded_credentials).split(':')
    else
        rc = 401
        error = 'Unsupported authentication scheme'

        [error, auth_header].each {|i| settings.logger.error(i) }
        halt rc, json_response(rc, ProvisionEngine::Error.new(rc, error, auth_header))
    end

    "#{username}:#{password}"
end

def body_valid?
    begin
        JSON.parse(request.body.read)
    rescue JSON::ParserError => e
        rc = 400
        error = 'Invalid JSON'

        [error, e.message].each {|i| settings.logger.error(i) }
        halt rc, json_response(rc, ProvisionEngine::Error.new(rc, error, e.message))
    end
end

def log_request(type)
    settings.logger.info("Received request to #{type}")
end

def log_response(level, code, data, message)
    if data.is_a?(String)
        body = data
    else
        body = data.to_json
    end

    settings.logger.info("#{RC}: #{code}")
    settings.logger.send(level, message)
    settings.logger.debug("Response Body: #{body}")
end
