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
# TODO: Decide install location. Customizable on the installer at the moment. Default value.
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
require 'data'
require 'function'

conf = ProvisionEngine::Configuration.new

case ARGV[0]
when 'start'
    logger = ProvisionEngine::Logger.new(conf[:log])

    logger.info "Using oned at #{conf[:one_xmlrpc]}"
    logger.info "Using oneflow at #{conf[:oneflow_server]}"

    ############################################################################
    # Define API Helpers
    ############################################################################

    RC = 'Response HTTP Return Code'.freeze
    RB = 'Response Body'.freeze
    SR = 'Serverless Runtime'.freeze
    SRD = 'Serverless Runtime definition'.freeze
    DENIED = 'Permission denied'.freeze
    SR_INVALID = "Invalid #{SRD}".freeze
    SR_NOT_FOUND = "#{SR} not found".freeze
    SR_FAIL = "Failed to create #{SR}".freeze

    # Helper method to return JSON responses
    def json_response(data, status)
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
        content = response[1]

        case rc
        when 201
            logger.info("#{RC}: #{rc}")
            logger.info("#{SR} created: #{content}")

            json_response(content, rc)
        when 400
            logger.error("#{RC}: #{rc}")
            logger.error("#{SR_INVALID}: #{content}")

            halt rc, json_response({ :message => SR_INVALID }, rc)
        when 403
            logger.error("#{RC}: #{rc}")
            logger.error("#{DENIED}: #{content}")

            halt rc, json_response({ :message => DENIED }, rc)
        when 422
            logger.error("#{RC}: #{rc}")
            logger.error("Unprocessable #{SRD}: #{content}")

            halt rc, json_response({ :message => DENIED }, rc)
        else
            logger.error("#{RC}: 500")
            logger.error("#{SR_FAIL}: #{content}")

            halt 500, json_response({ :message => SR_FAIL }, 500)
        end
    end

    get '/serverless-runtimes/:id' do
        auth = auth?

        client = ProvisionEngine::CloudClient.new(conf, auth)
        id = params[:id].to_i

        response = ProvisionEngine::ServerlessRuntime.get(client, id)
        rc = response[0]
        content = response[1]

        case rc
        when 200
            logger.info("#{RC}: #{rc}")
            logger.info("#{SR}: #{content}")

            json_response(runtime, rc)
        when 403
            logger.error("#{RC}: #{rc}")
            logger.error("#{DENIED}: #{content}")

            halt rc, json_response({ :message => DENIED }, rc)
        when 404
            logger.error("#{RC}: #{rc}")
            logger.error("#{SR_NOT_FOUND}: #{content}")

            halt rc, json_response({ :message => SR_NOT_FOUND }, rc)
        else
            logger.error("#{RC}: 500")
            logger.error("#{SR_FAIL}: #{content}")

            halt 500, json_response({ :message => SR_FAIL }, 500)
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
        content = response[1]

        case rc
        when 204
            logger.info("#{RC}: #{rc}")
            logger.info("#{SR} deleted")

            json_response(runtime, rc)
        when 403
            logger.error("#{RC}: #{rc}")
            logger.error("#{DENIED}: #{content}")

            halt rc, json_response({ :message => DENIED }, rc)
        when 404
            logger.error("#{RC}: #{rc}")
            logger.error("#{SR_NOT_FOUND}: #{content}")

            halt rc, json_response({ :message => SR_NOT_FOUND }, rc)
        else
            logger.error("#{RC}: 500")
            logger.error("#{SR_FAIL}: #{content}")

            halt 500, json_response({ :message => SR_FAIL }, 500)
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
