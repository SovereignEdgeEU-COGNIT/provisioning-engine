RSpec.shared_context 'crud' do |sr_template|
    it "create a #{SR}" do
        pp "Requesting #{SR} creation with template #{sr_template}"

        specification = JSON.load_file("templates/#{sr_template}")
        response = @conf[:engine_client].create(specification)

        expect(response.code).to eq(201)

        runtime = JSON.parse(response.body)
        pp runtime

        @conf[:id] = runtime['SERVERLESS_RUNTIME']['ID'].to_i

        validation = ProvisionEngine::ServerlessRuntime.validate(runtime)
        pp validation[1]

        raise validation[1] unless validation[0]

        @conf[:create] = true
    end

    it "read a #{SR}" do
        skip "#{SR} creation failed" unless @conf[:create]

        attempts = @conf[:conf][:timeouts][:get]

        1.upto(attempts) do |t|
            sleep 1
            expect(t == attempts).to be(false)

            response = @conf[:engine_client].get(@conf[:id])

            expect(response.code).to eq(200)

            runtime = JSON.parse(response.body)
            pp runtime

            # TODO: Check flow service for failed states like 7 => FAILED_DEPLOYING
            next unless runtime['SERVERLESS_RUNTIME']['FAAS']['STATE'] == 'ACTIVE'

            break
        end
    end

    it "not read a non existing #{SR}" do
        response = @conf[:engine_client].get(@conf[:id]+9001)

        expect(response.code).to eq(404)
    end

    it "not update #{SR}" do
        # skip "#{SR} creation failed" unless @conf[:create]
        response = @conf[:engine_client].update(@conf[:id], {})

        expect(response.code).to eq(501)

        body = JSON.parse(response.body)
        pp body

        expect(body).to eq('Serverless Runtime update not implemented')
    end

    it "not delete a non existing #{SR}" do
        response = @conf[:engine_client].delete(@conf[:id]+9001)

        expect(response.code).to eq(404)
    end

    it "delete a #{SR}" do
        skip "#{SR} creation failed" unless @conf[:create]

        wait_delete(@conf[:id])
    end
end
