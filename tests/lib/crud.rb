RSpec.shared_context 'crud' do |sr_template|
    it "create a #{SR}" do
        pp "Requesting #{SR} creation with template #{sr_template}"

        specification = File.read("templates/#{sr_template}")
        specification = JSON.parse(specification)

        response = rspec[:engine_client].create(specification)

        expect(response.code.to_i).to eq(201)

        runtime = JSON.parse(response.body)
        pp runtime

        rspec[:id] = runtime['SERVERLESS_RUNTIME']['ID'].to_i

        validation = ProvisionEngine::ServerlessRuntime.validate(runtime)
        pp validation[1]

        expect(validation[0]).to be(true)
    end

    it "read a #{SR}" do
        attempts = rspec[:conf][:timeouts][:get]

        1.upto(attempts) do |t|
            sleep 1
            expect(t == attempts).to be(false)

            response = rspec[:engine_client].get(rspec[:id])

            expect(response.code.to_i).to eq(200)

            runtime = JSON.parse(response.body)
            pp runtime

            # TODO: Check flow service for failed states like 7 => FAILED_DEPLOYING
            next unless runtime['SERVERLESS_RUNTIME']['FAAS']['STATE'] == 'ACTIVE'

            break
        end
    end

    it "not update #{SR}" do
        response = rspec[:engine_client].update(rspec[:id], {})

        expect(response.code.to_i).to eq(501)

        body = JSON.parse(response.body)
        pp body

        expect(body).to eq('Serverless Runtime update not implemented')
    end

    it "delete a #{SR}" do
        attempts = rspec[:conf][:timeouts][:get]

        1.upto(attempts) do |t|
            sleep 1
            expect(t == attempts).to be(false)

            response = rspec[:engine_client].delete(rspec[:id])
            rc = response.code.to_i

            next unless rc == 204

            expect(rc).to eq(204)

            break
        end
    end
end
