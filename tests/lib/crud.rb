RSpec.shared_context 'crud' do |sr_template|
    it "create a #{SR}" do
        pp "Requesting #{SR} creation with template #{sr_template}"

        specification = JSON.load_file("templates/#{sr_template}")
        response = @conf[:client][:engine].create(specification)
        @conf[:specification] = specification

        expect(response.code).to eq(201)

        runtime = JSON.parse(response.body)

        @conf[:id] = runtime['SERVERLESS_RUNTIME']['ID'].to_i
        @conf[:create] = true
    end

    it "read a #{SR}" do
        skip "#{SR} creation failed" unless @conf[:create]

        attempts = @conf[:conf][:timeouts][:get]

        1.upto(attempts) do |t|
            expect(t <= attempts).to be(true)
            sleep 1

            response = @conf[:client][:engine].get(@conf[:id])

            expect(response.code).to eq(200)

            runtime = JSON.parse(response.body)
            pp runtime

            case runtime['SERVERLESS_RUNTIME']['FAAS']['STATE']
            when 'ACTIVE'
                verify_sr_spec(@conf[:specification], runtime)
                break
            when 'FAILED'
                raise 'FaaS VM failed to deploy'
            else
                next
            end
        end
    end

    it "fail to update #{SR}" do
        # skip "#{SR} creation failed" unless @conf[:create]
        response = @conf[:client][:engine].update(@conf[:id], {})

        expect(response.code).to eq(501)

        body = JSON.parse(response.body)
        pp body

        expect(body).to eq('Serverless Runtime update not implemented')
    end

    it "delete a #{SR}" do
        skip "#{SR} creation failed" unless @conf[:create]

        verify_sr_delete(@conf[:id])
    end
end
