require 'sinatra'
require 'json'

module ProvisionEngine

    class API

        RETURN_CODE = 'Response HTTP Return Code'.freeze
        NOT_FOUND = 'Serverless Runtime not found'.freeze

        def initialize(config, cloud_client)
            @config = config
            @cloud_client = cloud_client
            setup_logger
            setup_routes
            run_server
        end

        def kill
            @logger.info("Killing API pid #{Process.pid}")
            Process.kill('INT', Process.pid)
        end

        private

        def setup_logger
            @logger = Logger.new(@config[:log], 'api')

            # Log API Calls
            before do
                @logger.info("API Call: #{request.request_method} #{request.fullpath}")
            end
        end

        def setup_routes
            post '/serverless-runtimes' do
                begin
                    request_body = JSON.parse(request.body.read)
                    id = @cloud_client.runtime_create(request_body)

                    @logger.info("#{RETURN_CODE}: 201")
                    @logger.info("Response Body: #{cloud_client.runtime_get(id)}")

                    json_response({ :id => id, **request_body }, 201)
                rescue JSON::ParserError => e
                    @logger.error("Invalid JSON: #{e.message}")
                    halt 400, json_response({ :message => 'Invalid JSON data' })
                end
            end

            get '/serverless-runtimes/:id' do
                id = params[:id].to_i
                runtime = @cloud_client.runtime_get(id)

                if runtime
                    @logger.info("#{RETURN_CODE}: 200")
                    @logger.info("Response Body: #{runtime}")

                    json_response(runtime)
                else
                    @logger.error("#{RETURN_CODE}: 404")
                    @logger.error(NOT_FOUND)

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

                        @logger.info("#{RETURN_CODE}: 200")
                        @logger.info("Response Body: #{cloud_client.runtime_get(id)}")

                        json_response({ :id => id, **request_body })
                    rescue JSON::ParserError => e
                        @logger.error("Invalid JSON: #{e.message}")
                        halt 400, json_response({ :message => 'Invalid JSON data' })
                    end
                else
                    @logger.error("#{RETURN_CODE}: 404")
                    @logger.error(NOT_FOUND)

                    halt 404, json_response({ :message => NOT_FOUND })
                end
            end

            delete '/serverless-runtimes/:id' do
                id = params[:id].to_i
                runtime = @cloud_client.runtime_get(id)

                if runtime
                    @cloud_client.runtime_delete(id)

                    @logger.info("#{RETURN_CODE}: 204")

                    status 204
                else
                    @logger.error("#{RETURN_CODE}: 404")
                    @logger.error(NOT_FOUND)

                    halt 404, json_response({ :message => NOT_FOUND })
                end
            end
        end

        def run_server
            set :bind, @config[:host]
            set :port, @config[:port]
            run!
        end

        # Helper method to return JSON responses
        def json_response(data, status = 200)
            content_type :json
            status status
            data.to_json
        end

    end

end
