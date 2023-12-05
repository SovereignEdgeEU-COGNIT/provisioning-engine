RSpec.shared_context 'auth' do
    it 'permission denied on Create service_template' do
        response = @conf[:client][:engine].create(generate_faas_minimal)

        expect([403, 422].include?(response.code)).to be(true)
        verify_error(response.body)
    end

    it 'permission denied on Create vm_template' do
        response = @conf[:client][:engine].create(generate_faas_minimal('DenyVMTemplate'))

        expect([403, 422].include?(response.code)).to be(true)
        verify_error(response.body)
    end

    it "Creating #{SR} for auth tests requiring an existing #{SR}" do
        @conf[:auth] = {}
        @conf[:auth][:sr_template] = generate_faas_minimal('Function')
        @conf[:auth][:engine_client_no_auth] = ProvisionEngine::Client.new(@conf[:endpoint])

        response = @conf[:client][:engine].create(@conf[:auth][:sr_template])

        expect(response.code).to eq(201)
        @conf[:auth][:create] = true

        runtime = JSON.parse(response.body)
        @conf[:auth][:id] = runtime[SRR]['ID'].to_i
    end

    it 'missing auth on Create' do
        response = @conf[:auth][:engine_client_no_auth].create(@conf[:auth][:sr_template])

        expect(response.code.to_i).to eq(401)
        verify_error(response.body)
    end

    it 'missing auth on Read' do
        skip "#{SR} creation failed" unless @conf[:auth][:create]

        response = @conf[:auth][:engine_client_no_auth].get(@conf[:auth][:id])

        expect(response.code.to_i).to eq(401)
        verify_error(response.body)
    end

    it 'missing auth on Update' do
        skip "#{SR} update not implemented"
    end

    it 'missing auth on Delete' do
        skip 'Creation did not succeed' unless @conf[:auth][:create]

        response = @conf[:auth][:engine_client_no_auth].delete(@conf[:auth][:id])

        expect(response.code.to_i).to eq(401)
        verify_error(response.body)
    end

    it 'create engine client with bad auth' do
        client = ProvisionEngine::Client.new(@conf[:endpoint], 'joe:mama')
        @conf[:auth][:engine_client_bad_auth] = client
    end

    it 'bad auth on Create' do
        response = @conf[:auth][:engine_client_bad_auth].create(@conf[:auth][:sr_template])

        expect(response.code).to eq(401)
        verify_error(response.body)
    end

    it 'bad auth on Read' do
        response = @conf[:auth][:engine_client_bad_auth].get(@conf[:auth][:id])

        expect([401, 404].include?(response.code)).to be(true)
        verify_error(response.body)
    end

    it 'bad auth on Update' do
        skip "#{SR} update not implemented"
    end

    it 'bad auth on Delete' do
        response = @conf[:auth][:engine_client_bad_auth].delete(@conf[:auth][:id])

        expect([401, 404].include?(response.code)).to be(true)
        verify_error(response.body)
    end

    it "delete #{SR} after auth tests have concluded" do
        skip "#{SR} creation failed" unless @conf[:auth][:create]

        verify_sr_delete(@conf[:auth][:id])
    end
end
