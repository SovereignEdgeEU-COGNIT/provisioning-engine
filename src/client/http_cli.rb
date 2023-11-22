#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'

class SimpleHttpClient

    # TODO: Load from one_auth env and files
    USERNAME = 'oneadmin'
    # PASSWORD = 'opennebula'
    PASSWORD = 'opennebulax'

    def initialize(url)
        @uri = URI.parse(url)
    end

    def get
        request(Net::HTTP::Get.new(@uri.request_uri))
    end

    def post(json_data)
        request_with_body(Net::HTTP::Post.new(@uri.request_uri), json_data)
    end

    def put(json_data)
        request_with_body(Net::HTTP::Put.new(@uri.request_uri), json_data)
    end

    def delete
        request(Net::HTTP::Delete.new(@uri.request_uri))
    end

    private

    def request_with_body(req, json_data)
        req.body = json_data.to_json
        req.content_type = 'application/json'

        request(req)
    end

    def request(req)
        req.basic_auth USERNAME, PASSWORD
        response = Net::HTTP.start(@uri.hostname, @uri.port,
                                   :use_ssl => @uri.scheme == 'https') do |http|
            http.request(req)
        end

        puts "Response Code: #{response.code}"

        return if response.is_a?(Net::HTTPNoContent)

        JSON.parse(response.body)
    end

end

# Command-line parsing
http_request_type = ARGV[0].downcase if ARGV[0]
uri = ARGV[1]
json_file_path = ARGV[2]

if ['get', 'post', 'put', 'delete'].include?(http_request_type) && uri
    client = SimpleHttpClient.new(uri)

    # Read JSON data from file if a path is provided for POST or PUT
    json_data = nil
    if json_file_path && ['post', 'put'].include?(http_request_type)
        begin
            json_data = JSON.parse(File.read(json_file_path))
        rescue Errno::ENOENT, JSON::ParserError
            puts "Failed to read or parse JSON from file: #{json_file_path}"
            exit 1
        end
    end

    response = case http_request_type
               when 'get'
                   client.get
               when 'post'
                   client.post(json_data)
               when 'put'
                   client.put(json_data)
               when 'delete'
                   client.delete
               end

    puts JSON.pretty_generate(response) if response
else
    puts 'CLI HTTP Client Usage:'
    puts 'client.rb [get|post|put|delete] <URI> <JSON file path (for POST and PUT only)>'
end
