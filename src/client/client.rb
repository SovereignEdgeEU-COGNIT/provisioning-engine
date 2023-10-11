require 'net/http'
require 'uri'

# To avoid conversions of status code str to int
class HTTPResponse < SimpleDelegator

    def code
        super.to_i
    end

end

module ProvisionEngine

    #
    # Specialized HTTP Client exposing engine specific API calls through instance methods
    #
    class Client

        #
        # Binds the client to an engine endpoint using a specific credentials
        #
        # @param [String] endpoint where the engine is running
        # @param [String] credentials in the form of user:pass
        #
        def initialize(endpoint, auth = nil)
            if auth.nil?
                @user = nil
                @pass = nil
            else
                unless auth.is_a?(String) && auth.include?(':')
                    raise 'Invalid auth data type, must be a string like <user>:<password>'
                end

                @user = auth.split(':')[0]
                @pass = auth.split(':')[1]
            end

            uri = URI.parse(endpoint)
            uri.scheme && uri.host
            @endpoint = endpoint
        end

        def create(specification)
            uri = URI.parse("#{@endpoint}/serverless-runtimes")
            request = Net::HTTP::Post.new(uri)

            do_request_with_body(request, uri, specification)
        end

        def get(id)
            uri = URI.parse("#{@endpoint}/serverless-runtimes/#{id}")
            request = Net::HTTP::Get.new(uri.request_uri)

            do_request(request, uri)
        end

        def update(id, specification)
            uri = URI.parse("#{@endpoint}/serverless-runtimes/#{id}")
            request = Net::HTTP::Put.new(uri)

            do_request_with_body(request, uri, specification)
        end

        def delete(id)
            uri = URI.parse("#{@endpoint}/serverless-runtimes/#{id}")
            request = Net::HTTP::Delete.new(uri.request_uri)

            do_request(request, uri)
        end

        private

        def do_request_with_body(request, uri, data)
            request.body = data.to_json
            request.content_type = 'application/json'

            do_request(request, uri)
        end

        def do_request(request, uri)
            request.basic_auth(@user, @pass) if @user && @pass
            http = Net::HTTP.new(uri.host, uri.port)
            HTTPResponse.new(http.request(request))
        end

    end

end
