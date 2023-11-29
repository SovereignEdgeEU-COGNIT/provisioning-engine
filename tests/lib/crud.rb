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

        response = @conf[:client][:engine].get(@conf[:id])
        expect(response.code).to eq(200)

        runtime = JSON.parse(response.body)
        verify_sr_spec(@conf[:specification], runtime)
    end

    it "fail to update #{SR}" do
        skip "#{SR} creation failed" unless @conf[:create]

        response = @conf[:client][:engine].update(@conf[:id], {})
        expect(response.code).to eq(200)

        runtime = JSON.parse(response.body)
        verify_sr_spec(@conf[:specification], runtime)
    end

    it "delete a #{SR}" do
        skip "#{SR} creation failed" unless @conf[:create]

        verify_sr_delete(@conf[:id])
    end
end
