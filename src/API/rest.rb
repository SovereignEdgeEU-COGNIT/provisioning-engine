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
    ############################################################################
    # Define API Helpers
    ############################################################################
    RC = 'Response HTTP Return Code'.freeze
    SR = 'Serverless Runtime'.freeze
    SRD = 'Serverless Runtime definition'.freeze
    DENIED = 'Permission denied'.freeze
    SR_NOT_FOUND = "#{SR} not found".freeze

    # Helper method to return JSON responses
    def json_response(status, data)
        content_type :json
        status status

        if data.is_a?(Hash)
            data.to_json
        else
            if (400..499).include?(status) || (500..599).include?(status)
                { :error => data }
            else
                { :message => data }
            end
        end
    end

    def auth?
        auth_header = request.env['HTTP_AUTHORIZATION']

        if auth_header.nil?
            rc = 401
            message = 'Authentication required'

            settings.logger.error(message)
            halt rc, json_response(rc, message)
        end

        if auth_header.start_with?('Basic ')
            encoded_credentials = auth_header.split(' ')[1]
            username, password = Base64.decode64(encoded_credentials).split(':')
        else
            rc = 401
            message = 'Unsupported authentication scheme'

            settings.logger.error(message)
            halt rc, json_response(rc, message)
        end

        "#{username}:#{password}"
    end

    def body_valid?
        begin
            JSON.parse(request.body.read)
        rescue JSON::ParserError => e
            rc = 400
            settings.logger.error("Invalid JSON: #{e.message}")
            halt rc, json_response(rc, 'Invalid JSON data')
        end
    end

    def log_request(type)
        settings.logger.info("Received request to #{type}")
    end

    def log_response(level, code, body, message)
        settings.logger.info("#{RC}: #{code}")
        settings.logger.debug("Response Body: #{body}")
        settings.logger.send(level, message)
    end

    ############################################################################
    # API configuration
    ############################################################################

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
        call = "API Call: #{request.request_method} #{request.fullpath} #{request.body.read}"
        settings.logger.debug(call)
        request.body.rewind
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
        log_request("Get a #{SR}")

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
        log_request("Update a #{SR}")

        rc = 501
        message = "#{SR} update not implemented"

        settings.logger.error("#{SR} update not implemented")
        halt rc, json_response(rc, message)

        auth = auth?
        specification = body_valid?

        client = ProvisionEngine::CloudClient.new(conf, auth)

        id = params[:id].to_i

        client.runtime_update(id, specification)
    end

    delete '/serverless-runtimes/:id' do
        log_request("Delete a #{SR}")

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
