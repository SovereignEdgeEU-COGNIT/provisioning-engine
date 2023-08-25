#!/usr/bin/env ruby

############################################################################
# Environment Configuration
############################################################################
ONE_LOCATION = ENV['ONE_LOCATION']

if !ONE_LOCATION
    RUBY_LIB_LOCATION = '/usr/lib/one/ruby'
    GEMS_LOCATION     = '/usr/share/one/gems'
else
    RUBY_LIB_LOCATION = ONE_LOCATION + '/lib/ruby'
    GEMS_LOCATION     = ONE_LOCATION + '/share/gems'
end

if File.directory?(GEMS_LOCATION)
    real_gems_path = File.realpath(GEMS_LOCATION)
    if !defined?(Gem) || Gem.path != [real_gems_path]
        $LOAD_PATH.reject! {|l| l =~ /vendor_ruby/ }
        require 'rubygems'
        Gem.use_paths(real_gems_path)
    end
end

$LOAD_PATH << RUBY_LIB_LOCATION
$LOAD_PATH << '/opt/provision-engine/'

# Shared Libraries for Modules
require 'json'
require 'yaml'
require 'base64'
require 'sinatra'

# OpenNebula Libraries
require 'opennebula'
require 'opennebula/oneflow_client'

# Engine Modules
require 'log'
require 'configuration'
require 'client'

require 'runtime'

conf = ProvisionEngine::Configuration.new

case ARGV[0]
when 'start'
    logger = ProvisionEngine::Logger.new(conf[:log])

    logger.info "Using oned at #{conf[:one_xmlrpc]}"
    logger.info "Using oneflow at #{conf[:oneflow_server]}"

    ############################################################################
    # Define API Helpers
    ############################################################################

    SR = 'Serverless Runtime'.freeze
    SRD = 'Serverless Runtime definition'.freeze
    DENIED = 'Permission denied'.freeze
    SR_NOT_FOUND = "#{SR} not found".freeze

    # Helper method to return JSON responses
    def json_response(status, data)
        content_type :json
        status status
        data.is_a?(String) ? data : data.to_json
    end

    def auth?
        auth_header = request.env['HTTP_AUTHORIZATION']

        if auth_header.nil?
            logger.error("#{RC}: 401")
            halt 401, json_response({ :message => 'Authentication required' }, 401)
        end

        if auth_header.start_with?('Basic ')
            encoded_credentials = auth_header.split(' ')[1]
            username, password = Base64.decode64(encoded_credentials).split(':')
        else
            logger.error("#{RC}: 401")
            halt 401, json_response({ :message => 'Unsupported authentication scheme' }, 401)
        end

        "#{username}:#{password}"
    end

    def body_valid?
        begin
            JSON.parse(request.body.read)
        rescue JSON::ParserError => e
            logger.error("Invalid JSON: #{e.message}")
            halt 400, json_response({ :message => 'Invalid JSON data' })
        end
    end

    def log_response(level, code, body, message)
        logger.send(level, "Response HTTP Return Code: #{code}")
        logger.send(level, "Response Body: #{body}")
        logger.send(level, message)
    end

    ############################################################################
    # API configuration
    ############################################################################

    set :bind, conf[:host]
    set :port, conf[:port]

    ############################################################################
    # Routes setup
    ############################################################################

    # Log every HTTP Request received
    before do
        logger.info("API Call: #{request.request_method} #{request.fullpath}")
    end

    post '/serverless-runtimes' do
        auth = auth?
        specification = body_valid?

        client = ProvisionEngine::CloudClient.new(conf, auth)

        response = ProvisionEngine::ServerlessRuntime.create(client, specification)
        rc = response[0]
        rb = response[1]

        case rc
        when 201
            log_response('info', rc, rb, "#{SR} created")
            json_response(rc, rb)
        when 400
            log_response('error', rc, rb, "Invalid #{SRD}")
            halt rc, json_response(rc, rb)
        when 403
            log_response('error', rc, rb, DENIED)
            halt rc, json_response(rc, rb)
        when 422
            log_response('error', rc, rb, "Unprocessable #{SRD}")
            halt rc, json_response(rc, rb)
        else
            log_response('error', rc, rb, "Failed to create #{SR}")
            halt 500, json_response(500, rb)
        end
    end

    get '/serverless-runtimes/:id' do
        auth = auth?

        client = ProvisionEngine::CloudClient.new(conf, auth)
        id = params[:id].to_i

        response = ProvisionEngine::ServerlessRuntime.get(client, id)
        rc = response[0]
        rb = response[1]

        case rc
        when 200
            log_response('info', rc, rb, SR)
            json_response(rc, rb)
        when 403
            halt rc, json_response(rc, rb)
        when 404
            log_response('error', rc, rb, SR_NOT_FOUND)
            halt rc, json_response(rc, rb)
        else
            log_response('error', rc, rb, "Failed to get #{SR}")
            halt 500, json_response(500, rb)
        end
    end

    put '/serverless-runtimes/:id' do
        logger.error("#{RC}: 501")
        logger.error("#{SR} update not implemented")

        halt 501, json_response({ :message => "#{SR} update not implemented" }, 501)

        auth = auth?
        specification = body_valid?

        client = ProvisionEngine::CloudClient.new(conf, auth)

        id = params[:id].to_i

        response = client.runtime_update(id, specification)
    end

    delete '/serverless-runtimes/:id' do
        auth = auth?

        id = params[:id].to_i

        client = ProvisionEngine::CloudClient.new(conf, auth)

        response = client.runtime_delete(client, id)
        rc = response[0]
        rb = response[1]

        case rc
        when 204
            log_response('info', rc, rb, "#{SR} created")
            json_response(rc, rb)
        when 403
            log_response('error', rc, rb, DENIED)
            halt rc, json_response(rc, rb)
        when 404
            log_response('error', rc, rb, SR_NOT_FOUND)
            halt rc, json_response(rc, rb)
        else
            log_response('error', rc, rb, "Failed to delete #{SR}")
            halt 500, json_response(500, rb)
        end
    end

when 'stop'
    process_name = 'provision-engine'
    pid = `pidof #{process_name}`.to_i

    # TODO: reuse log file
    puts('Stopping Provision Engine')
    Process.kill('INT', pid)
else
    STDERR.puts('Unknown engine control')
end
