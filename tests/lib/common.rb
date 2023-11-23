SR = 'Serverless Runtime'.freeze

############################################################################
# RSpec methods
############################################################################

def examples?(examples, conf, params = nil)
    include_context(examples, params) if conf[:examples][examples]
end

def verify_sr_spec(specification, runtime)
    [specification, runtime].each do |sr|
        response = ProvisionEngine::ServerlessRuntime.validate(sr)

        raise response[1] unless response[0] == 200
    end

    specification = specification['SERVERLESS_RUNTIME']
    runtime = runtime['SERVERLESS_RUNTIME']

    # optional name has been applied if given
    expect(runtime['NAME']).to eq(specification['NAME']) if specification['NAME']

    # mandatory information is present on SR object
    ['SERVICE_ID', 'DEVICE_INFO', 'SCHEDULING'].each do |mandatory|
        expect(runtime.key?(mandatory)).to be(true)
    end

    # service has been created
    response = @conf[:client][:oneflow].get("/service/#{runtime['SERVICE_ID']}")
    expect(response.code.to_i).to eq(200)

    ['FAAS', 'DAAS'].each do |role|
        next unless specification[role] && !specification[role]['FLAVOUR'].empty?

        vm = OpenNebula::VirtualMachine.new_with_id(runtime[role]['VM_ID'], @conf[:client][:oned])
        raise "Error getting #{SR} VM" if OpenNebula.is_error?(vm.info)

        # mandatory role information exists
        ['FLAVOUR', 'VM_ID', 'STATE', 'ENDPOINT'].each do |mandatory|
            expect(runtime[role].key?(mandatory)).to be(true)
        end

        # optional role information exists if given
        ['CPU', 'VCPU', 'MEMORY', 'DISK_SIZE'].each do |optional|
            next unless specification[role][optional]

            expect(runtime[role][optional]).to eq(specification[role][optional])
        end

        # rubocop:disable Style/StringLiterals
        # verify VM has correct resources
        ['CPU', 'VCPU', 'MEMORY'].each do |capacity|
            next unless specification[role][capacity]

            expect(vm["//TEMPLATE/#{capacity}"].to_f).to eq(specification[role][capacity].to_f)
        end

        expect(runtime[role]['ENDPOINT']).to eq(vm["//TEMPLATE/NIC[NIC_ID=\"0\"]/IP"].to_s)

        if specification[role]['DISK_SIZE']
            expect(vm["//TEMPLATE/DISK[DISK_ID=\"0\"]/SIZE"].to_i).to eq(specification[role]['DISK_SIZE'])
        end
        # rubocop:enable Style/StringLiterals
    end
end

def verify_sr_delete(sr_id)
    response = @conf[:client][:engine].delete(sr_id)

    case response.code
    when 204
        verify_service_delete(sr_id)
    when 423
        attempts = @conf[:conf][:timeouts][:get]
        1.upto(attempts) do |t|
            expect(t <= attempts).to be(true)
            sleep 1

            response = @conf[:client][:engine].delete(sr_id)
            case response.code
            when 423
                pp "Waiting for #{SR} to reach end state"
                next
            when 204
                verify_service_delete(sr_id)
                break
            when 500
                raise 'Server error, check logs'
            else
                raise "Unexpected error code: #{response.code}"
            end
        end
    when 500
        raise 'Server error, check logs'
    else
        raise "Unexpected error code: #{response.code}"
    end
end

def verify_service_delete(sr_id)
    attempts = @conf[:conf][:timeouts][:delete]
    1.upto(attempts) do |t|
        expect(t <= attempts).to be(true)
        sleep 1

        response = @conf[:client][:oneflow].get("/service/#{sr_id}")
        rc = response.code.to_i

        next if rc == 200

        break
    end
end

def verify_error(body)
    expect(ProvisionEngine.error?(body)).to be(true)
end

############################################################################
# Helpers
############################################################################

def random_string
    chars = ('a'..'z').to_a + ('A'..'Z').to_a
    string = ''
    8.times { string << chars[SecureRandom.rand(chars.size)] }
    string
end

def generate_faas_minimal(flavour = nil)
    if !flavour
        flavour = random_string
        pp "rolled a random flavour #{flavour}"
    end
    {
        'SERVERLESS_RUNTIME' => {
            'NAME' => flavour,
            'FAAS' => {
                'FLAVOUR' => flavour
            },
            'SCHEDULING' => {},
            'DEVICE_INFO' => {}
        }
    }
end
