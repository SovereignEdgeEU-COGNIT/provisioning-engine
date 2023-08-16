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
    DENIED = 'Permission denied'.freeze
    SR_INVALID = "Invalid #{SR} defition".freeze
    SR_NOT_FOUND = "#{SR} not found".freeze
    SR_FAIL = "Failed to create #{SR}".freeze

    # Helper method to return JSON responses
    def json_response(data, status)
        content_type :json
        status status
        data.is_a?(String) ? data : data.to_json
    end

    def auth?(request)
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
        auth = auth?(request)

        begin
            request_body = JSON.parse(request.body.read)
        rescue JSON::ParserError => e
            logger.error("Invalid JSON: #{e.message}")
            halt 400, json_response({ :message => 'Invalid JSON data' })
        end

        client = ProvisionEngine::CloudClient.new(conf, auth)

        # creation = client.runtime_create(request_body)

        require 'net/http'
        require 'uri'

        uri = URI.parse('http://127.0.0.1:1339/service_template/0')
        http = Net::HTTP.new(uri.host, uri.port)

        request = Net::HTTP::Get.new(uri.request_uri)
        request.basic_auth('oneadmin', 'opennebula')

        response = http.request(request)
        json_response(response.body, response.code)

        # case creation[0]
        # when 0
        #     response = creation[1]

        #     logger.info("#{RC}: 201")
        #     logger.info("Serverless Runtime created: #{response}")

        #     json_response(response, 201)
        # when 400
        #     logger.error("#{RC}: 400")
        #     logger.error("#{SR_INVALID}: #{response}")
        #     halt 400, json_response({ :message => SR_INVALID }, 400)
        # when 403
        #     logger.error("#{RC}: 403")
        #     logger.error("#{DENIED}: #{response}")
        #     halt 403, json_response({ :message => DENIED }, 403)
        # else
        #     logger.error("#{RC}: 500")
        #     logger.error("#{SR_FAIL}: #{response}")
        #     halt 500, json_response({ :message => SR_FAIL }, 500)
        # end
    end

    get '/serverless-runtimes/:id' do
        auth = auth?(request)

        id = params[:id].to_i
        client = ProvisionEngine::CloudClient.new(conf, auth)
        runtime = client.runtime_get(id)

        if runtime
            logger.info("#{RC}: 200")
            logger.info("#{RB}: #{runtime}")

            json_response(runtime)
        else
            logger.error("#{RC}: 404")
            logger.error(SR_NOT_FOUND)

            halt 404, json_response({ :message => SR_NOT_FOUND })
        end
    end

    put '/serverless-runtimes/:id' do
        id = params[:id].to_i
        runtime = @cloud_client.runtime_get(id)

        if runtime
            begin
                request_body = JSON.parse(request.body.read)
                @cloud_client.runtime_update(id, request_body)

                logger.info("#{RC}: 200")
                logger.info("#{RB}: #{cloud_client.runtime_get(id)}")

                json_response({ :id => id, **request_body })
            rescue JSON::ParserError => e
                logger.error("Invalid JSON: #{e.message}")
                halt 400, json_response({ :message => 'Invalid JSON data' })
            end
        else
            logger.error("#{RC}: 404")
            logger.error(SR_NOT_FOUND)

            halt 404, json_response({ :message => SR_NOT_FOUND })
        end
    end

    delete '/serverless-runtimes/:id' do
        id = params[:id].to_i
        runtime = @cloud_client.runtime_get(id)

        if runtime
            @cloud_client.runtime_delete(id)

            logger.info("#{RC}: 204")

            status 204
        else
            logger.error("#{RC}: 404")
            logger.error(SR_NOT_FOUND)

            halt 404, json_response({ :message => SR_NOT_FOUND })
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
