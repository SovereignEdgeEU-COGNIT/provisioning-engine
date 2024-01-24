SR = 'Serverless Runtime'.freeze
SRR = 'SERVERLESS_RUNTIME'.freeze
T = '//TEMPLATE/'.freeze

HARDWARE = {
    'CPU' => 1,
    'MEMORY' => 64,
    'DISK_SIZE' => 128
}

############################################################################
# RSpec methods
############################################################################

def load_examples(params = nil)
    include_context(examples, params) if conf[:examples][examples]
end

def verify_sr_spec(specification, runtime)
    [specification, runtime].each do |sr|
        response = ProvisionEngine::ServerlessRuntime.validate(sr)

        raise response[1] unless response[0] == 200
    end

    specification = specification[SRR]
    runtime = runtime[SRR]

    #############################
    # Verify runtime infomation #
    #############################

    expect(runtime['NAME']).to eq(specification['NAME']) if specification['NAME']
    expect(runtime.key?('SERVICE_ID')).to be(true)

    ['DEVICE_INFO', 'SCHEDULING'].each do |schevice|
        next unless specification[schevice] || specification[schevice].empty?

        specification[schevice].each do |sd|
            expect(vm['//USER_TEMPLATE/'][sd]).to eq(sd)
        end
    end

    response = @conf[:client][:oneflow].get("/service/#{runtime['SERVICE_ID']}")
    expect(response.code.to_i).to eq(200) # service has been created

    ##############################
    # Verify function information #
    ##############################
    ProvisionEngine::Function::FUNCTIONS.each do |role|
        next unless specification[role] && !specification[role]['FLAVOUR'].empty?

        vm = OpenNebula::VirtualMachine.new_with_id(runtime[role]['VM_ID'], @conf[:client][:oned])

        response = vm.info

        if OpenNebula.is_error?(response)
            raise "Error getting #{SR} function VM #{role} \n#{response.message}"
        end

        nic = "#{T}NIC[NIC_ID=\"0\"]/"

        # mandatory role information exists
        ['FLAVOUR', 'VM_ID', 'STATE', 'ENDPOINT'].each do |mandatory|
            expect(runtime[role].key?(mandatory)).to be(true)
        end

        # optional role information exists if given
        ['CPU', 'VCPU', 'MEMORY', 'DISK_SIZE'].each do |optional|
            next unless specification[role][optional]

            expect(runtime[role][optional]).to eq(specification[role][optional])
        end

        # verify VM has correct resources
        ['CPU', 'VCPU', 'MEMORY'].each do |capacity|
            next unless specification[role][capacity]

            expect(vm["#{T}#{capacity}"].to_f).to eq(specification[role][capacity].to_f)
        end

        ['EXTERNAL_IP', 'IP6', 'IP'].each do |address|
            if vm["#{nic}#{address}"]
                expect(runtime[role]['ENDPOINT']).to eq(vm["#{nic}#{address}"])
                break
            end
        end

        if specification[role]['DISK_SIZE']
            expect(vm["#{T}DISK[DISK_ID=\"0\"]/SIZE"].to_i).to eq(specification[role]['DISK_SIZE'])
        end

        if vm["#{T}ERROR"]
            expect(runtime[role]['STATE']).to eq('ERROR')
            expect(runtime[role]['ERROR']).to eq(vm["#{T}ERROR"])
        end
    end
end

def verify_sr_delete(sr_id)
    response = @conf[:client][:engine].delete(sr_id)

    case response.code
    when 204
        verify_service_delete(sr_id)
    when 423
        attempts = @conf[:conf][:tests][:timeouts][:get]
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
    attempts = @conf[:conf][:tests][:timeouts][:delete]
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
        SRR => {
            'NAME' => flavour,
            'FAAS' => {
                'FLAVOUR' => flavour
            },
            'SCHEDULING' => {},
            'DEVICE_INFO' => {}
        }
    }
end

def increase_runtime_hardware(specification, mode = 'multiply')
    ProvisionEngine::Function::FUNCTIONS.each do |function|
        next unless specification[SRR][function]

        case mode
        when 'multiply'
            HARDWARE.keys.each do |h|
                next if specification[SRR][function][h].nil?

                specification[SRR][function][h] = specification[SRR][function][h] * 2
            end
        when 'increase'
            HARDWARE.each do |key, value|
                next if specification[SRR][function][key].nil?

                specification[SRR][function][key] = specification[SRR][function][key] + value
            end

        else
            raise "Invalid #{SR} hardware update mode"
        end
    end
end

def rename_runtime(specification, name = SecureRandom.alphanumeric)
    specification[SRR]['NAME'] = name
end

def strip_consequential_info(specification)
    ['ID', 'SERVICE_ID'].each do |ri|
        specification[SRR].delete(ri)
    end

    ProvisionEngine::Function::FUNCTIONS.each do |function|
        next unless specification[SRR][function]

        ['VM_ID', 'STATE'].each do |fi|
            specification[SRR][function].delete(fi)
        end
    end
end
