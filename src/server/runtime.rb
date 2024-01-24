module ProvisionEngine

    #
    # Document that references a service running functions specified by a client
    #
    class ServerlessRuntime < OpenNebula::DocumentJSON

        DOCUMENT_TYPE = 1337
        SCHEMA = JSON.load_file('/etc/provision-engine/schemas/serverless_runtime.json').freeze

        SR = 'Serverless Runtime'.freeze
        SRR = 'SERVERLESS_RUNTIME'.freeze
        SRD = "#{SR} Document".freeze
        SRF = 'Serverless Runtime Function VM'.freeze
        SRS = "#{SR} Service".freeze
        SRS_NOT_FOUND = "#{SRS} not found".freeze
        SRS_NO_READ = "Failed to read #{SRS}".freeze
        SRS_NO_DELETE = "Failed to delete #{SRS}".freeze

        attr_accessor :cclient, :body

        #
        # Creates Serverless Runtime Document and its backing service
        #
        # @param [CloudClient] client OpenNebula interface
        # @param [Hash] specification Serverless Runtime definition
        #
        # @return [Array] [Response Code, Serverless Runtime Document/Error]
        #
        def self.create(client, specification)
            response = ServerlessRuntime.validate(specification)
            return response unless response[0] == 200

            specification = specification[SRR]

            response = ServerlessRuntime.to_service(client, specification)
            return response unless response[0] == 200

            service_id = response[1]['DOCUMENT']['ID'].to_i
            specification['SERVICE_ID'] = service_id

            client.logger.info("#{SRS} #{service_id} created")

            response = ServerlessRuntime.sync(client, specification)
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
                    message << "#{SRS_NO_DELETE} #{service_id}"
                    message << response[1]
                end

                return ProvisionEngine::Error.new(rc, error, message)
            end

            client.logger.info("Created #{SRD}")

            runtime.info

            [201, runtime]
        end

        #
        # Loads an existing Serverless Runtime
        #
        # @param [CloudClient] client OpenNebula interface
        # @param [Int] id Serverless Runtime Document ID
        #
        # @return [Array] [Response Code, Serverless Runtime Document/Error]
        #
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

            document.cclient = client
            document.update
        end

        #
        # Syncronizes the Serverless Runtime backing components with the document
        #
        # @return [Array] [Response Code, ServerlessRuntime/error]
        #
        def update
            cclient?
            initial_state = to_hash

            response = ProvisionEngine::ServerlessRuntime.sync(@cclient, @body)
            return response unless response[0] == 200

            return [200, self] if to_hash == initial_state

            @cclient.logger.info("Updating #{SRD} #{@id}")
            response = super()

            if OpenNebula.is_error?(response)
                rc = ProvisionEngine::Error.map_error_oned(response.errno)
                error = "Failed to update #{SR} #{@id}"
                return ProvisionEngine::Error.new(rc, error, response.error)
            end

            [200, self]
        end

        #
        # Updates the Serverless Runtime document and its backing components
        #
        # @param [Hash] specification Desired Serverless Runtime state
        #
        # @return [Array] [Response Code, Serverless Runtime Document/Error]
        #
        def update_sr(specification)
            cclient?

            response = ServerlessRuntime.validate(specification)
            return response unless response[0] == 200

            rename?(specification)
            specification = specification[SRR]

            ProvisionEngine::Function::FUNCTIONS.each do |function|
                next if specification[function].nil? || specification[function]['FLAVOUR'].empty?

                vm_id = @body[function]['VM_ID']
                if vm_id.nil?
                    rc = 500
                    error = "No VM_ID found for function #{function}"
                    return ProvisionEngine::Error.new(rc, error)
                end

                vm = ProvisionEngine::Function.new_with_id(vm_id, @cclient.client_oned)
                response = vm.info

                if OpenNebula.is_error?(response)
                    rc = ProvisionEngine::Error.map_error_oned(response.errno)
                    error = "Failed to read #{SRF} #{function}"
                    return ProvisionEngine::Error.new(rc, error, response.message)
                end

                @cclient.logger.info "Looking for changes for function #{function}"

                changes = specification[function].dup.delete_if do |k, v|
                    @body[function][k] == v
                end

                @cclient.logger.debug changes

                # Resize VM hardware
                case vm.state_function
                when ProvisionEngine::Function::STATES[:updating], ProvisionEngine::Function::STATES[:pending]
                    rc = 423
                    error = "Cannot update #{SRF} #{function} on a transient state"
                    return ProvisionEngine::Error.new(rc, error, vm.state_function)
                when ProvisionEngine::Function::STATES[:error]
                    vm.recover(2) # retry

                    err = "Cannot update #{SRF} #{function} on an error state. A recovery was attempted"
                    return ProvisionEngine::Error.new(500, err, error)
                when ProvisionEngine::Function::STATES[:running]
                    ['capacity', 'disk'].each do |resource|
                        response = vm.public_send("resize_#{resource}?", specification[function],
                                                  @cclient.logger)
                        return response unless response[0] == 200

                        1.upto(@cclient.conf[:timeout]) do |t|
                            vm.info

                            if t == @cclient.conf[:timeout]
                                rc = 504
                                error = "#{SRF} #{function} stuck while updating capabilities"
                                return ProvisionEngine::Error.new(rc, error, vm.state_function)
                            end

                            case vm.state_function
                            when ProvisionEngine::Function::STATES[:running]
                                break
                            when ProvisionEngine::Function::STATES[:updating]
                                sleep 1
                                next
                            else
                                rc = 500
                                error = "#{SRF} #{function} entered unexpected state"
                                return ProvisionEngine::Error.new(rc, error, vm.state_function)
                            end
                        end
                    end

                end

                # Update document body and VMs USER_TEMPLATE
                ['SCHEDULING', 'DEVICE_INFO'].each do |schevice|
                    next if specification[function][schevice].nil?
                    next if specification[function][schevice] == @body[SRR][function][schevice]

                    @body[SRR][function][schevice] = specification[function][schevice]
                    vm.update(specification[function][schevice], true)

                    next unless OpenNebula.is_error?(response)

                    rc = ProvisionEngine::Error.map_error_oned(response.errno)
                    error = "Failed to update #{SRF} #{schevice}"
                    return ProvisionEngine::Error.new(rc, error, response.message)
                end

                vm.resched # Just the flag. Responsability lies on scheduler
            end

            update
        end

        #
        # Deletes a Serverless Runtime Document and its backing components
        #
        # @return [Array] [Response Code, ''/Error]
        #
        def delete
            cclient? && @cclient.logger.info("Deleting #{SRS}")

            document = JSON.parse(to_json)
            service_id = document['DOCUMENT']['TEMPLATE']['BODY']['SERVICE_ID']

            response = @cclient.service_delete(service_id)
            rc = response[0]

            @cclient.logger.warning(SRS_NOT_FOUND) if rc == 404

            if ![204, 404].include?(rc)
                error = "#{SRS_NO_DELETE} #{service_id}"
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
        # @return [Array] [200,''] or [400, Error]
        #
        def self.validate(specification)
            begin
                JSON::Validator.validate!(SCHEMA, specification)
                [200, '']
            rescue JSON::Schema::ValidationError => e
                ProvisionEngine::Error.new(400, "Invalid #{SR} specification", e.message)
            end
        end

        #####################
        # Service Management
        #####################

        #
        # Updates Serverless Runtime definition based on the underlying elements state
        #
        # @param [CloudClient] client OpenNebula interface
        # @param [Hash] specification Serverless Runtime definition to be updated
        #
        # @return [Array] [Response Code, ''/Error]
        #
        def self.sync(client, specification)
            service_id = specification['SERVICE_ID']
            service = nil

            1.upto(client.conf[:timeout]) do |t|
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
                        error = "#{SRS_NO_READ} #{service_id}"
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
                        id = role['nodes'][0]['vm_info']['VM']['ID'].to_i

                        response = ProvisionEngine::Function.get(client.client_oned, id)
                        return response unless response[0] == 200

                        vm = response[1]

                        specification[role['name']].merge!(vm.to_function)
                    end

                    return [200, '']
                end
            end
        end

        #
        # Create oneflow service based on Serverless Runtime specification
        #
        # @param [CloudClient] OpenNebula interface
        # @param [Hash] specification Serverless Runtime specification
        #
        # @return [Array] [Response Code, Service Document Body/'Error']
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

                ProvisionEngine::Function::FUNCTIONS.each do |role|
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

                        vm_template = rb

                        if !vm_template.template_like_str('//TEMPLATE/DISK')
                            error = 'Function VM template does not have associated DISK'
                            return ProvisionEngine::Error.new(500, error)
                        end

                        override = ProvisionEngine::Function.vm_template_contents(specification[role], vm_template,
                                                                                  client.conf[:capacity])

                        client.logger.info("Applying \"vm_template_contents\" to role #{role}")
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
                        message << "#{SRS_NO_DELETE} #{service_id}"
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

        #
        # Perform recovery operations on the Serverless Runtime backing components
        #
        # @return [Array] [Response Code, Service Document Body/Error]
        #
        def recover
            response = @cclient.service_recover(service_id)
            rc = response[0]

            if rc != 204
                error = "Failed to recover #{SRS} #{service_id}"
                return ProvisionEngine::Error.new(rc, error, response[1])
            end

            response = @cclient.service_get(service_id)
            rc = response[0]

            if rc != 200
                error = "#{SRS_NO_READ} #{service_id}"
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
        # Renames the Serverless Runtime Document if the specification demands it
        #
        # @param [Hash] specification Serverless Runtime specification with desired state
        #
        # @return [Array] [Response Code, ''/Error]
        #
        def rename?(specification)
            new_name = specification[SRR]['NAME']

            return [200, ''] unless new_name && new_name != name

            @cclient.logger.info("Renaming #{SRD} #{@id}")
            @cclient.logger.debug("From: #{name} To: #{new_name}")

            response = rename(new_name)

            if OpenNebula.is_error?(response)
                rc = ProvisionEngine::Error.map_error_oned(response.errno)
                error = "Failed to rename #{SR}"

                return ProvisionEngine::Error.new(rc, error, response.error)
            end

            return [200, ''] unless name != new_name

            error = "Failed to rename #{SR}"
            message = "#{SRD} name \"#{name}\" mismatches target name #{new_name} after succesful rename operation"

            return ProvisionEngine::Error.new(rc, error, message)
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
        # Translates the Serverless Runtime document body a SCHEMA compatible Hash
        #
        # @return [Hash] Serverless Runtime representation
        #
        def to_sr
            load?

            runtime = {
                SRR => {
                    :NAME => name,
                    :ID => id
                }
            }
            rsr = runtime[SRR]

            rsr.merge!(@body)
            rsr.delete('registration_time')

            runtime
        end

        def service_id
            load?
            @body[SRR]['SERVICE_ID']
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

        def cclient?
            raise "Missing #{SR} Cloud Client" unless @cclient
        end

    end

end
