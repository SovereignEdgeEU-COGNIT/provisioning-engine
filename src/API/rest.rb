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

    RETURN_CODE = 'Response HTTP Return Code'.freeze
    NOT_FOUND = 'Serverless Runtime not found'.freeze

    # Helper method to return JSON responses
    def json_response(data, status = 200)
        content_type :json
        status status
        data.to_json
    end

    def auth?(request)
        auth_header = request.env['HTTP_AUTHORIZATION']

        if auth_header.nil?
            logger.error("#{RETURN_CODE}: 401")
            halt 401, json_response({ :message => 'Authentication required' })
        end

        if auth_header.start_with?('Basic ')
            encoded_credentials = auth_header.split(' ')[1]
            username, password = Base64.decode64(encoded_credentials).split(':')
        else
            logger.error("#{RETURN_CODE}: 401")
            halt 401, json_response({ :message => 'Unsupported authentication scheme' })
        end

        "#{username}:#{password}"
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
        begin
            request_body = JSON.parse(request.body.read)
            id = @cloud_client.runtime_create(request_body)

            logger.info("#{RETURN_CODE}: 201")
            logger.info("Response Body: #{cloud_client.runtime_get(id)}")

            json_response({ :id => id, **request_body }, 201)
        rescue JSON::ParserError => e
            logger.error("Invalid JSON: #{e.message}")
            halt 400, json_response({ :message => 'Invalid JSON data' })
        end
    end

    get '/serverless-runtimes/:id' do
        auth = auth?(request)

        id = params[:id].to_i
        runtime = ProvisionEngine::CloudClient.new(settings.conf, auth).runtime_get(id)

        if runtime
            logger.info("#{RETURN_CODE}: 200")
            logger.info("Response Body: #{runtime}")

            json_response(runtime)
        else
            logger.error("#{RETURN_CODE}: 404")
            logger.error(NOT_FOUND)

            halt 404, json_response({ :message => NOT_FOUND })
        end
    end

    put '/serverless-runtimes/:id' do
        id = params[:id].to_i
        runtime = @cloud_client.runtime_get(id)

        if runtime
            begin
                request_body = JSON.parse(request.body.read)
                @cloud_client.runtime_update(id, request_body)

                logger.info("#{RETURN_CODE}: 200")
                logger.info("Response Body: #{cloud_client.runtime_get(id)}")

                json_response({ :id => id, **request_body })
            rescue JSON::ParserError => e
                logger.error("Invalid JSON: #{e.message}")
                halt 400, json_response({ :message => 'Invalid JSON data' })
            end
        else
            logger.error("#{RETURN_CODE}: 404")
            logger.error(NOT_FOUND)

            halt 404, json_response({ :message => NOT_FOUND })
        end
    end

    delete '/serverless-runtimes/:id' do
        id = params[:id].to_i
        runtime = @cloud_client.runtime_get(id)

        if runtime
            @cloud_client.runtime_delete(id)

            logger.info("#{RETURN_CODE}: 204")

            status 204
        else
            logger.error("#{RETURN_CODE}: 404")
            logger.error(NOT_FOUND)

            halt 404, json_response({ :message => NOT_FOUND })
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
