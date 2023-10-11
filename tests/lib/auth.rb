RSpec.shared_context 'auth' do
    it "Creating #{SR} for auth tests requring an existing #{SR}" do
        @conf[:auth] = {}
        @conf[:auth][:sr_template] = JSON.load_file('templates/sr_minimal.json')
        @conf[:auth][:engine_client_no_auth] = ProvisionEngine::Client.new(@conf[:endpoint])

        response = @conf[:engine_client].create(@conf[:auth][:sr_template])

        expect(response.code).to eq(201)
        @conf[:auth][:create] = true

        runtime = JSON.parse(response.body)
        @conf[:auth][:id] = runtime['SERVERLESS_RUNTIME']['ID'].to_i
    end

    it 'missing auth on Create' do
        response = @conf[:auth][:engine_client_no_auth].create(@conf[:auth][:sr_template])
        expect(response.code.to_i).to eq(401)
    end

    it 'missing auth on Read' do
        skip "#{SR} creation failed" unless @conf[:auth][:create]

        response = @conf[:auth][:engine_client_no_auth].get(@conf[:auth][:id])
        expect(response.code.to_i).to eq(401)
    end

    it 'missing auth on Update' do
        skip "#{SR} update not implemented"
    end

    it 'missing auth on Delete' do
        skip 'Creation did not succeed' unless @conf[:auth][:create]

        response = @conf[:auth][:engine_client_no_auth].delete(@conf[:auth][:id])
        expect(response.code.to_i).to eq(401)
    end

    it 'create engine client with bad auth' do
        client = ProvisionEngine::Client.new(@conf[:endpoint], 'joe:mama')
        @conf[:auth][:engine_client_bad_auth] = client
    end

    it 'bad auth on Create' do
        response = @conf[:auth][:engine_client_bad_auth].create(@conf[:auth][:sr_template])

        expect(response.code).to eq(401)
    end

    it 'bad auth on Read' do
        response = @conf[:auth][:engine_client_bad_auth].get(@conf[:auth][:id])

        # DocumentJSON.info doesn't have map_error
        expect([401, 404].include?(response.code)).to be(true)
    end

    it 'bad auth on Update' do
        skip "#{SR} update not implemented"
    end

    it 'bad auth on Delete' do
        response = @conf[:auth][:engine_client_bad_auth].delete(@conf[:auth][:id])

        # DocumentJSON.info doesn't have error code
        expect([401, 404].include?(response.code)).to be(true)
    end

    it "delete #{SR} after auth tests have concluded" do
        skip "#{SR} creation failed" unless @conf[:auth][:create]

        wait_delete(@conf[:auth][:id])
    end
end
