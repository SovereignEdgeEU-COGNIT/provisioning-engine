RSpec.shared_context 'crud_invalid' do
    it "fail to create a #{SR} with invalid FLAVOUR" do
        response = @conf[:client][:engine].create(generate_faas_minimal)

        expect(response.code).to eq(422)
        verify_error(response.body)
    end

    it "fail to create a #{SR} with invalid schema" do
        specification = {
            'SERVERLESS_RUNTIME' => {
                'FAAS' => {
                    'FLAVOUR' => 'Function'
                },
                'DAAS' => {}, # DAAS should not exist or have FLAVOUR at least
                'SCHEDULING' => {},
                'DEVICE_INFO' => {}
            }
        }

        response = @conf[:client][:engine].create(specification)

        expect(response.code).to eq(400)
        verify_error(response.body)
    end

    # requires a flow template FAILED_DEPLOY which guarantees service on FAILED_DEPLOY
    it "fail to create #{SR} if oneflow service enters FAIL_DEPLOY" do
        specification = {
            'SERVERLESS_RUNTIME' => {
                'FAAS' => {
                    'FLAVOUR' => 'FAILED_DEPLOY'
                },
                'SCHEDULING' => {},
                'DEVICE_INFO' => {}
            }
        }

        response = @conf[:client][:engine].create(specification)

        expect(response.code).to eq(500)
        body = JSON.parse(response.body)
        verify_error(body)

        ['error', 'message'].each do |k|
            expect(body.key?(k) && !body[k].empty?).to be(true)
        end
    end

    it "fail to read a non existing #{SR}" do
        @conf[:invalid] = {}
        @conf[:invalid][:sky] = 2147483647 # biggest ID for a pool element

        response = @conf[:client][:engine].get(@conf[:invalid][:sky])

        expect(response.code).to eq(404)
        verify_error(response.body)
    end

    it "fail to update a non existing #{SR}" do
        response = @conf[:client][:engine].update(@conf[:invalid][:sky], {})

        expect(response.code).to eq(501)
        # expect(response.code).to eq(404)
        verify_error(response.body)
    end

    it "fail to delete a non existing #{SR}" do
        response = @conf[:client][:engine].delete(@conf[:invalid][:sky])

        expect(response.code).to eq(404)
        verify_error(response.body)
    end

    it "create #{SR} for document type verification" do
        template = generate_faas_minimal('Function')
        response = @conf[:client][:engine].create(template)

        expect(response.code).to eq(201)
        body = JSON.parse(response.body)

        @conf[:invalid][:id] = body['SERVERLESS_RUNTIME']['ID'].to_i
        @conf[:invalid][:service_id] = body['SERVERLESS_RUNTIME']['SERVICE_ID'].to_i
    end

    ['get', 'delete'].each do |operation|
        it "fail to #{operation} an existing non #{SR} document" do
            response = @conf[:client][:engine].public_send(operation, @conf[:invalid][:service_id])

            expect(response.code).to eq(404)
            verify_error(response.body)
        end
    end

    it "delete required #{SR}" do
        response = @conf[:client][:engine].delete(@conf[:invalid][:id])
        expect(response.code).to eq(204)
    end
end
