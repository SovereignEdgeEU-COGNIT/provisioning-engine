RSpec.shared_context 'server_info' do
    it 'engine version can be queried through API' do
        response = Net::HTTP.get_response(URI("#{@conf[:endpoint]}/server/version"))
        expect(response.code).to eq('200')

        body = JSON.parse(response.body)
        expect(valid_semantic_version?(body)).to be(true)
    end

    it '/etc/provision-engine/engine.conf matches loaded config' do
        response = Net::HTTP.get_response(URI("#{@conf[:endpoint]}/server/config"))
        expect(response.code).to eq('200')

        body = JSON.parse(response.body)
        expect(deep_symbolize_keys(body) == @conf[:conf][:engine]).to be(true)
    end

    it '/etc/provision-engine/schemas/serverless_runtime.json matches current branch schema' do
        response = Net::HTTP.get_response(URI("#{@conf[:endpoint]}/serverless-runtimes/schema"))
        expect(response.code).to eq('200')

        body = JSON.parse(response.body)
        expect(body == ProvisionEngine::ServerlessRuntime::SCHEMA).to be(true)
    end
end

def valid_semantic_version?(version)
    version.match?(/\A\d+\.\d+\.\d+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?\z/)
end

def deep_symbolize_keys(hash)
    hash.each_with_object({}) do |(key, value), result|
        new_key = key.to_sym
        new_value = value.is_a?(Hash) ? deep_symbolize_keys(value) : value
        result[new_key] = new_value
    end
end
