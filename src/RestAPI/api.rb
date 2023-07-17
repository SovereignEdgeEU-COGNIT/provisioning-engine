require 'sinatra'
require 'json'

# In-memory storage for serverless runtimes (Replace with a persistent storage mechanism in a production environment)
$serverless_runtimes = {}

# Create Serverless Runtime
post '/serverless-runtimes' do
    request.body.rewind
    data = JSON.parse(request.body.read)

    # Generate a unique ID for the serverless runtime
    id = SecureRandom.uuid

    # Store the serverless runtime
    $serverless_runtimes[id] = data

    status 201
    content_type :json
    { :id => id, :serverless_runtime => data }.to_json
end
    
# Retrieve Serverless Runtime
get '/serverless-runtimes/:id' do |id|
    serverless_runtime = $serverless_runtimes[id]

    if serverless_runtime
        status 200
        content_type :json
        { :id => id, :serverless_runtime => serverless_runtime }.to_json
    else
        status 404
    end
end

# Update Serverless Runtime
put '/serverless-runtimes/:id' do |id|
    request.body.rewind
    data = JSON.parse(request.body.read)

    if $serverless_runtimes.key?(id)
        $serverless_runtimes[id] = data

        status 200
        content_type :json
        { :id => id, :serverless_runtime => data }.to_json
    else
        status 404
    end
end

# Delete Serverless Runtime
delete '/serverless-runtimes/:id' do |id|
    if $serverless_runtimes.key?(id)
        $serverless_runtimes.delete(id)
        status 204
    else
        status 404
    end
end
