require 'sinatra'

module ProvisionEngine

    class API

        # Start the REST API with log level and system configuration
        def initialize(config, cloud_client)
            log_config = config[:log]
            host = config[:host]
            port = config[:port]

            logger = Log.new(log_config, 'api')

            # Log API call with info log level
            before do
                logger.info("API Call: #{request.request_method} #{request.fullpath}")
            end

            # Create Serverless Runtime
            post '/serverless-runtimes' do
                request_body = JSON.parse(request.body.read)
                id = cloud_client.function_create(request_body)

                logger.info('Response HTTP Return Code: 201')
                logger.info("Response Body: #{cloud_client.function_get(id)}")

                json_response({ :id => id, **request_body }, 201)
            end

            # Retrieve Serverless Runtime
            get '/serverless-runtimes/:id' do
                id = params[:id].to_i
                faas_function = cloud_client.function_get(id)

                if faas_function
                    logger.info('Response HTTP Return Code: 200')
                    logger.info("Response Body: #{faas_function}")

                    json_response(faas_function)
                else
                    logger.error('Response HTTP Return Code: 404')
                    logger.error('Response Body: { "message": "Serverless Runtime not found" }')

                    status 404
                    json_response({ :message => 'Serverless Runtime not found' })
                end
            end

            # Update Serverless Runtime
            put '/serverless-runtimes/:id' do
                id = params[:id].to_i
                faas_function = cloud_client.function_get(id)

                if faas_function
                    request_body = JSON.parse(request.body.read)
                    cloud_client.function_update(id, request_body)

                    logger.info('Response HTTP Return Code: 200')
                    logger.info("Response Body: #{cloud_client.function_get(id)}")

                    json_response({ :id => id, **request_body })
                else
                    logger.error('Response HTTP Return Code: 404')
                    logger.error('Response Body: { "message": "Serverless Runtime not found" }')

                    status 404
                    json_response({ :message => 'Serverless Runtime not found' })
                end
            end

            # Delete Serverless Runtime
            delete '/serverless-runtimes/:id' do
                id = params[:id].to_i
                faas_function = cloud_client.function_get(id)

                if faas_function
                    cloud_client.function_delete(id)

                    logger.info('Response HTTP Return Code: 204')

                    status 204
                else
                    logger.error('Response HTTP Return Code: 404')
                    logger.error('Response Body: { "message": "Serverless Runtime not found" }')

                    status 404
                    json_response({ :message => 'Serverless Runtime not found' })
                end
            end

            set :bind, host
            set :port, port

            @pid = Process.pid
            run!
        end

        def kill
            @logger.info("Killing API pid #{@pid}")
            Process.kill('INT', @pid)
        end

        private

        # Helper method to return JSON responses
        def json_response(data, status = 200)
            content_type :json
            status status
            data.to_json
        end

    end

end
