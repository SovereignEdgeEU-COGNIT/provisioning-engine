RSpec.shared_context 'crud' do |sr_template|
    it "create a #{SR}" do
        pp "Requesting #{SR} creation with template #{sr_template}"

        specification = JSON.load_file("templates/#{sr_template}")
        response = @conf[:client][:engine].create(specification)
        @conf[:specification] = specification

        expect(response.code).to eq(201)

        runtime = JSON.parse(response.body)

        @conf[:id] = runtime[SRR]['ID'].to_i
        @conf[:create] = true
    end

    it "read a #{SR}" do
        skip "#{SR} creation failed" unless @conf[:create]

        response = @conf[:client][:engine].get(@conf[:id])
        expect(response.code).to eq(200)

        runtime = JSON.parse(response.body)
        verify_sr_spec(@conf[:specification], runtime)

        strip_consequential_info(runtime)
        @conf[:runtime] = runtime
    end

    # VM reaches RUNNING state eventually
    # only updates the specified functions
    # only updates what is different from the existing function
    # missing properties will be ignored
    #   for the time being only:
    #      updates CPU, MEMORY and DISK
    #      rename document
    # runtime ID, service ID and Function IDs remain the same
    it "update #{SR}" do
        skip "#{SR} creation failed" unless @conf[:create]

        increase_runtime_hardware(@conf[:runtime], 'increase')
        rename_runtime(@conf[:runtime])

        timeout = @conf[:conf][:tests][:timeouts][:get]
        1.upto(timeout) do |t|
            if t == timeout
                raise "Timeout reached for #{SR} deployment"
            end

            response = @conf[:client][:engine].update(@conf[:id], @conf[:runtime])
            rc = response.code
            body = JSON.parse(response.body)

            case rc
            when 200
                verify_sr_spec(@conf[:runtime], body, true)
                break
            when 423
                pp "Waiting for #{SR} to be RUNNING"
                verify_error(body)

                sleep 1
                next
            else
                pp body
                verify_error(body)

                raise "Unexpected error code #{rc}"
            end
        end
    end

    it "delete a #{SR}" do
        skip "#{SR} creation failed" unless @conf[:create]

        verify_sr_delete(@conf[:id])
    end
end
