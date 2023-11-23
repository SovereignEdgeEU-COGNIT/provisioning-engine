module ProvisionEngine

    #
    # Document that references a service running functions specified by a client
    #
    class ServerlessRuntime < OpenNebula::DocumentJSON

        DOCUMENT_TYPE = 1337
        SCHEMA = JSON.load_file('/etc/provision-engine/schemas/serverless_runtime.json').freeze

        SR = 'Serverless Runtime'.freeze
        SRD = "#{SR} Document".freeze
        SRS = "#{SR} Service".freeze
        SRS_NOT_FOUND = "#{SRS} not found".freeze
        SRS_NO_READ = "Failed to read #{SRS}".freeze
        SERVICE_NO_DELETE = 'Failed to delete service'.freeze

        FUNCTION_STATES = ['PENDING', 'RUNNING', 'UPDATING', 'ERROR'].freeze
        FUNCTION_LCM_STATES = {
            FUNCTION_STATES[0] => [
                'LCM_INIT',
                'BOOT',
                'PROLOG',
                'BOOT_UNKNOWN',
                'BOOT_POWEROFF',
                'BOOT_SUSPENDED',
                'BOOT_STOPPED',
                'BOOT_UNDEPLOY',
                'PROLOG_UNDEPLOY',
                'CLEANUP_RESUBMIT'
            ],
            FUNCTION_STATES[1] => ['RUNNING'],
            FUNCTION_STATES[3] => [
                'FAILURE',
                'UNKNOWN',
                'BOOT_FAILURE',
                'BOOT_MIGRATE_FAILURE',
                'BOOT_UNDEPLOY_FAILURE',
                'BOOT_STOPPED_FAILURE',
                'PROLOG_FAILURE',
                'PROLOG_MIGRATE_FAILURE',
                'PROLOG_MIGRATE_POWEROFF_FAILURE',
                'PROLOG_MIGRATE_SUSPEND_FAILURE',
                'PROLOG_RESUME_FAILURE',
                'PROLOG_UNDEPLOY_FAILURE',
                'PROLOG_MIGRATE_UNKNOWN',
                'PROLOG_MIGRATE_UNKNOWN_FAILURE'
            ]
        }.freeze

        attr_accessor :cclient, :body

        def self.create(client, specification)
            response = ServerlessRuntime.validate(specification)
            return response unless response[0] == 200

            specification = specification['SERVERLESS_RUNTIME']

            response = ServerlessRuntime.to_service(client, specification)
            return response unless response[0] == 200

            client.logger.debug_dev(response)

            service_id = response[1]['DOCUMENT']['ID'].to_i
            specification['SERVICE_ID'] = service_id

            client.logger.info("#{SRS} #{service_id} created")

            response = ServerlessRuntime.sync(client, specification, service_id)
            return response unless response[0] == 200

            client.logger.info("Creating #{SRD}")
            client.logger.debug(specification)

            xml = ServerlessRuntime.build_xml
            runtime = ServerlessRuntime.new(xml, client.client_oned)

            response = runtime.allocate(specification)
            if OpenNebula.is_error?(response)
                error = "Failed to create #{SRD}"
                rc = ProvisionEngine::Error.map_error_oned(response.errno)
                message = response.message

                response = client.service_destroy(service_id)

                if response[0] != 204
                    message << "#{SERVICE_NO_DELETE} #{service_id}"
                    message << response[1]
                end

                return ProvisionEngine::Error.new(rc, error, message)
            end

            client.logger.info("Created #{SRD}")

            runtime.info

            [201, runtime]
        end

        def self.get(client, id)
            document = ServerlessRuntime.new_with_id(id, client.client_oned)
            response = document.info

            if OpenNebula.is_error?(response)
                rc = ProvisionEngine::Error.map_error_oned(response.errno)

                if rc == 404 || ProvisionEngine::Error.wrong_document_type?(rc, response.message)
                    rc = 404 if rc != 404
                    error = SR_NOT_FOUND
                    message = ''
                else
                    error = "Failed to read #{SRD}"
                    message = response.message
                end

                return ProvisionEngine::Error.new(rc, error, message)
            end

            runtime = document
            body = runtime.body

            response = ServerlessRuntime.sync(client, body, body['SERVICE_ID'])
            return response if response[0] != 200

            runtime.update
            runtime.cclient = client

            [200, runtime]
        end

        def delete
            raise "Missing #{SR} Cloud Client" unless @cclient

            @cclient.logger.info("Deleting #{SRS}")

            document = JSON.parse(to_json)
            service_id = document['DOCUMENT']['TEMPLATE']['BODY']['SERVICE_ID']

            response = @cclient.service_delete(service_id)
            rc = response[0]

            @cclient.logger.warning(SRS_NOT_FOUND) if rc == 404

            if rc != 204
                error = "#{SERVICE_NO_DELETE} #{service_id}"
                message = response[1]

                [error, message].each {|i| @cclient.logger.error(i) }

                response = @cclient.service_destroy(service_id)

                if response[0] != 204
                    message << response[1]
                    return ProvisionEngine::Error.new(500, error, message)
                end
            end

            @cclient.logger.info("Deleting #{SRD}")

            response = super()

            if OpenNebula.is_error?(response)
                rc = ProvisionEngine::Error.map_error_oned(response.errno)
                error = "Failed to delete #{SRD}"
                return ProvisionEngine::Error.new(rc, error, response.message)
            end

            @cclient.logger.info("#{SRD} deleted")
            [204, '']
        end

        #
        # Validates the Serverless Runtime specification using the distributed schema
        #
        # @param [Hash] specification a runtime specification
        #
        # @return [Array] [true,''] or [false, 'reason']
        #
        def self.validate(specification)
            begin
                JSON::Validator.validate!(SCHEMA, specification)
                [200, '']
            rescue JSON::Schema::ValidationError => e
                ProvisionEngine::Error.new(400, "Invalid #{SR} specification", e.message)
            end
        end

        #
        # Updates Serverless Runtime definition based on the underlying elements state
        #
        # @param [CloudClient] client OpenNebula interface
        # @param [Hash] runtime Serverless Runtime definition to be updated
        # @param [Integer] service_id OneFlow service ID mapped to the Serverless Runtime
        # @param [Integer] timeout How long to wait for Role VMs to be created
        #
        # TODO: timeout is hardcoded
        def self.sync(client, runtime, service_id, timeout = 30)
            service = nil

            1.upto(timeout) do |t|
                catch(:query_service) do
                    if t == 30
                        error = "OpenNebula did not create VMs for the #{SRS} #{service_id}"
                        service_log = service['DOCUMENT']['TEMPLATE']['BODY']['log']

                        return ProvisionEngine::Error.new(504, error, service_log)
                    end

                    response = client.service_get(service_id)
                    rc = response[0]
                    rb = response[1]

                    if rc != 200
                        error = "Failed to read #{SRS}"
                        return ProvisionEngine::Error.new(rc, error, rb)
                    end

                    service = rb
                    roles = service['DOCUMENT']['TEMPLATE']['BODY']['roles']

                    roles.each do |role|
                        next unless role['nodes'].size < role['cardinality']

                        msg = "Waiting #{t} seconds for service role #{role['name']} VMs"
                        client.logger.info(msg)
                        sleep 1

                        throw(:query_service)
                    end

                    client.logger.debug(service)

                    roles.each do |role|
                        runtime[role['name']].merge!(xaas_template(client, role))
                    end

                    return [200, '']
                end
            end
        end

        #####################
        # Service Management
        #####################

        #
        # Create oneflow service based on Serverless Runtime specification
        #
        # @param [CloudClient] OpenNebula interface
        # @param [Hash] specification Serverless Runtime specification
        #
        # @return [Array] Response Code and Body of the operation
        #
        def self.to_service(client, specification)
            response = client.service_template_pool_get
            rc = response[0]
            rb = response[1]

            if rc != 200
                error = 'Failed to get list of service templates'
                return ProvisionEngine::Error.new(rc, error, rb)
            end

            if rb['DOCUMENT_POOL'].empty?
                error = "User requesting #{SR} creation has no flow templates available for use"
                return ProvisionEngine::Error.new(403, error)
            end

            service_templates = rb['DOCUMENT_POOL']['DOCUMENT']
            tuple = ServerlessRuntime.tuple(specification)

            # find flow_template matching flavour tuple
            service_templates.each do |service_template|
                next unless service_template['NAME'] == tuple

                merge_template = {
                    'roles' => []
                }
                schevice=''

                ['SCHEDULING', 'DEVICE_INFO'].each do |i|
                    next unless specification.key?(i)

                    i_template = ''
                    specification[i].each do |property, value|
                        i_template << "#{property}=\"#{value}\",\n" if value
                    end

                    if !i_template.empty?
                        i_template.reverse!.sub!("\n", '').reverse!
                        i_template.reverse!.sub!(',', '').reverse!
                    end

                    schevice << "#{i}=[#{i_template}]\n"
                end

                ['FAAS', 'DAAS'].each do |role|
                    next unless specification[role] && !specification[role]['FLAVOUR'].empty?

                    service_template['TEMPLATE']['BODY']['roles'].each do |service_template_role|
                        next unless service_template_role['name'] == role

                        response = client.vm_template_get(service_template_role['vm_template'])
                        rc = response[0]
                        rb = response[1]

                        if rc != 200
                            error = "Failed to read VM Template for Function #{role}"

                            return ProvisionEngine::Error.new(rc, error, rb)
                        end

                        override = function_requierements(specification[role], rb,
                                                          client.conf[:capacity])

                        client.logger.info("Applying vm_template_contents to role #{role}")
                        client.logger.debug(override)

                        merge_template['roles'] << {
                            'name' => role,
                            'vm_template_contents' => "#{override}\n#{schevice}"
                        }
                    end
                end

                response = client.service_template_instantiate(service_template['ID'],
                                                               merge_template)
                rc = response[0]
                rb = response[1]

                if rc != 201
                    error = "Failed to create #{SRS}"
                    return ProvisionEngine::Error.new(rc, error, rb)
                end

                service_id = rb['DOCUMENT']['ID'].to_i

                response = client.service_get(service_id)
                rc = response[0]
                rb = response[1]

                if rc != 200
                    error = SRS_NO_READ
                    return ProvisionEngine::Error.new(rc, error, rb)
                end

                service = rb
                client.logger.debug(service)

                if client.service_fail?(service)
                    error = "#{SRS} #{service_id} entered FAILED state after creation"
                    message = service['DOCUMENT']['TEMPLATE']['BODY']['log']

                    response = client.service_destroy(service_id)
                    if response[0] != 204
                        message << "#{SERVICE_NO_DELETE} #{service_id}"
                        message << response[1]
                    end

                    response = ProvisionEngine::Error.new(500, error, message)
                end

                return response
            end

            error = "Cannot find a valid service template for the specified flavours: #{tuple}"
            message = { 'FAAS' => specification['FAAS'] }
            message['DAAS'] = specification['FAAS'] if specification['DAAS']

            ProvisionEngine::Error.new(422, error, message)
        end

        def recover(service_id)
            response = @cclient.service_recover(service_id)
            rc = response[0]

            if rc != 204
                error = "Failed to recover #{SRS} #{service_id}"
                return ProvisionEngine::Error.new(rc, error, response[1])
            end

            response = @cclient.service_get(service_id)
            rc = response[0]

            if rc != 200
                error = SRS_NO_READ
                return ProvisionEngine::Error.new(rc, error, response[1])
            end

            service = response[1]

            if @cclient.service_fail?(service)
                error = "Cannot recover #{service_id} from failure"
                service_log = service['DOCUMENT']['TEMPLATE']['BODY']['log']

                return ProvisionEngine::Error.new(rc, error, service_log)
            end

            [200, service]
        end

        #
        # Generates oneflow service vm_template_contents for a given role
        # based on a Serverless Runtime Function specification
        #
        # @param [Hash] specification Function specification found in Serverless Runtime definition
        # @param [OpenNebula::Template] vm_template Function baseline VM template
        # @param [Hash] conf_capacity Engine configuration attribute for max capacity assumptions
        #
        # @return [String] vm_template contents for a oneflow service template
        #
        def self.function_requierements(role_specification, vm_template, conf_capacity)
            disk_size = role_specification['DISK_SIZE']
            xaas = []

            xaas << "HOT_RESIZE=[CPU_HOT_ADD_ENABLED=\"YES\",\nMEMORY_HOT_ADD_ENABLED=\"YES\"]"
            xaas << 'MEMORY_RESIZE_MODE="BALLOONING"'

            if disk_size
                disk_template = vm_template.template_like_str('//TEMPLATE/DISK')

                if disk_template.include?('SIZE=')
                    disk_template.sub!("SIZE=\d+", "SIZE=\"#{disk_size}\"")
                else
                    disk_template << "\n#{"SIZE=\"#{disk_size}\""}"
                end

                disk_template.gsub!(/"$/, '",').reverse!.sub!(',', '').reverse!
                xaas << "DISK=[#{disk_template}]"
            end

            if role_specification['CPU']
                xaas << "CPU=#{role_specification['CPU']}"
                xaas << "VCPU=#{role_specification['CPU']}"

                vcpu_max = role_specification['CPU'] * conf_capacity[:max][:vcpu_mult]
            else # get upper limit from mult * vm_template_vcpu
                vcpu = vm_template['//TEMPLATE/VCPU'].to_i
                vcpu = conf_capacity[:default][:vcpu] if vcpu.zero?

                vcpu_max = vcpu * conf_capacity[:max][:vcpu_mult]
            end
            if role_specification['MEMORY']
                xaas << "MEMORY=#{role_specification['MEMORY']}"

                memory_max = role_specification['MEMORY'] * conf_capacity[:max][:memory_mult]
            else # get upper limit from mult * vm_template_memory
                memory = vm_template['//TEMPLATE/MEMORY'].to_i
                memory = conf_capacity[:default][:memory] if memory.zero?

                memory_max = memory * conf_capacity[:max][:memory_mult]
            end

            xaas << "VCPU_MAX= \"#{vcpu_max}\""
            xaas << "MEMORY_MAX=\"#{memory_max}\""

            xaas.join("\n")
        end

        #
        # Creates a runtime function hash for the Serverless Runtime document
        #
        # @param [CloudClient] OpenNebula interface
        # @param [Hash] role oneflow service role information
        #
        # @return [Hash] Function hash
        #
        def self.xaas_template(client, role)
            vm_info = role['nodes'][0]['vm_info']['VM']
            vm_id = vm_info['ID'].to_i

            response = client.vm_get(vm_id)
            rc = response[0]
            rb = response[1]

            return response unless rc == 200

            vm = rb
            xaas_template = {}
            t = '//TEMPLATE/'
            nic = "#{t}NIC[NIC_ID=\"0\"]/"

            xaas_template['VM_ID'] = vm_id
            xaas_template['STATE'] = map_vm_state(vm)

            if xaas_template['STATE'] == 'ERROR'
                if vm["#{t}ERROR"]
                    xaas_template['ERROR'] = vm["#{t}ERROR"]
                else
                    xaas_template['ERROR'] = 'No VM Error from Cloud Edge Manager'
                end
            end

            if nic
                ['EXTERNAL_IP', 'IP6', 'IP'].each do |address| # Priority order
                    if vm["#{nic}#{address}"]
                        xaas_template['ENDPOINT'] = vm["#{nic}#{address}"]
                        break
                    end
                end
            end
            # No ENDPOINT will result in empty string
            xaas_template['ENDPOINT'] = '' unless xaas_template['ENDPOINT']

            xaas_template['CPU'] = vm["#{t}VCPU"].to_i
            xaas_template['MEMORY'] = vm["#{t}MEMORY"].to_i
            xaas_template['DISK_SIZE'] = vm["#{t}DISK[DISK_ID=\"0\"]/SIZE"].to_i

            xaas_template
        end

        #
        # Maps an OpenNebula VM state to the accepted Function VM states
        #
        # @param [OpenNebula::VirtualMachine] vm Virtual Machine representing the Function
        #
        # @return [String] Serverless Runtime Function state
        #
        def self.map_vm_state(vm)
            case vm.state_str
            when 'INIT', 'PENDING', 'HOLD'
                FUNCTION_STATES[0]
            when 'ACTIVE'
                FUNCTION_LCM_STATES.each do |function_state, vm_states|
                    return function_state if vm_states.include?(vm.lcm_state_str)
                end
            when 'STOPPED', 'SUSPENDED', 'POWEROFF', 'UNDEPLOYED', 'CLONING'
                FUNCTION_STATES[2]
            else
                FUNCTION_STATES[3]
            end
        end

        #####################
        # Inherited Functions
        #####################

        # Service must have been created prior to allocating the document
        def allocate(specification)
            specification['registration_time'] = Integer(Time.now)

            if specification['NAME']
                name = specification['NAME']
            else
                name = "#{ServerlessRuntime.tuple(specification)}_#{SecureRandom.uuid}"
            end

            super(specification.to_json, name)
        end

        #################
        # Helpers
        #################

        #
        # Translates the Serverless Runtime document to the SCHEMA
        #
        # @return [Hash] Serverless Runtime definition
        #
        def to_sr
            load?

            runtime = {
                :SERVERLESS_RUNTIME => {
                    :NAME => name,
                    :ID => id
                }
            }
            rsr = runtime[:SERVERLESS_RUNTIME]

            rsr.merge!(@body)
            rsr.delete('registration_time')

            runtime
        end

        #
        # Generates the flow template name for the service instantiation
        #
        # @param [Hash] specification Serverless Runtime root level specification
        #
        # @return [String] FaasName possibly + -DaasName if DaaS flavour is specified
        #
        def self.tuple(specification)
            tuple = specification['FAAS']['FLAVOUR']

            if specification['DAAS'] && !specification['DAAS']['FLAVOUR'].empty?
                tuple << "-#{specification['DAAS']['FLAVOUR']}"
            end

            tuple
        end

        def load?
            load_body if @body.nil?
        end

    end

end
