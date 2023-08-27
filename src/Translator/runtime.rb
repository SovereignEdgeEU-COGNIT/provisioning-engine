module ProvisionEngine

    # Serverless runtime class as wrapper of DocumentJSON
    class ServerlessRuntime < OpenNebula::DocumentJSON

        DOCUMENT_TYPE = 1337

        def self.create(client, specification)
            if !ServerlessRuntime.validate(specification)
                message = 'Invalid Serverless Runtime specification'
                return [400, message]
            end

            # Create service

            response = ServerlessRuntime.to_service(client, specification)
            rc = response[0]
            rb = response[1]

            return [rc, rb] if rc != 201

            # When the service instantiates it has no running VMs
            # TODO: Wait for running VMs ? Wait for running service ? Runtime is stateless though ?
            response = client.service_get(rb["DOCUMENT"]["ID"])
            rc = response[0]
            rb = response[1]

            return [rc, rb] if rc != 200

            service = rb

            # TODO: reuse the same CloudClient logfile for a single engine execution
            logger = Logger.new(client.conf[:log], 'CloudClient')
            logger.debug('---------Serverless Runtime Service-------------')
            logger.debug(service)

            # Create document from specification + created service state
            specification['SERVICE_ID'] = service['DOCUMENT']['ID']x``

            service_template = service['DOCUMENT']['TEMPLATE']['BODY']
            roles = service_template['roles']


            specification['FAAS'].merge!(xaas_template(client, roles[0]))
            specification['DAAS'].merge!(xaas_template(client, roles[1])) if roles[1]

            # Register Serverless Runtime json as OpenNebula document

            xml = ServerlessRuntime.build_xml
            runtime = ServerlessRuntime.new(xml, client)
            response = runtime.allocate(specification.to_json)

            if OpenNebula.is_error?(response)
                return [ServerlessRuntime.map_error_oned(response.errno), response.message]
            end

            runtime.info

            [201, runtime]
        end

        def self.get(client, id)
            runtime = ServerlessRuntime.new_with_id(client, id)
            runtime.info

            return [404, 'Document not found'] if runtime.name.nil?

            [200, runtime]
        end

        # TODO
        def update(client, id, changes, options = { :append => false })
            runtime = ServerlessRuntime.new_with_id(client, id)
            runtime.info

            return [404, 'Document not found'] if runtime.name.nil?

            # Update VMs ?

            # Update service

            # Update document

            runtime.update(changes, options[:append])

            [200, runtime]
        end

        def delete(client, id)
            runtime = ServerlessRuntime.new_with_id(client, id)
            runtime.info

            return [404, 'Document not found'] if runtime.name.nil?

            runtime.load_body
            service_id = runtime.body['DOCUMENT']['TEMPLATE']['BODY']['SERVICE_ID']

            response = client.service_delete(service_id)
            rc = response.code.to_i
            rb = JSON.parse(response.body)

            return [rc, rb] if rc != 204

            response = runtime.delete

            if OpenNebula.is_error?(response)
                return [self.class.map_error_oned(response.errno), response.message]
            end

            [204, '']
        end

        #####################
        # Inherited Functions
        #####################

        # Service must have been created prior to allocating the document
        def allocate(specification)
            specification['registration_time'] = Integer(Time.now)

            super(specification.to_json, specification['NAME'])
        end

        #################
        # Helpers
        #################

        # TODO: Validate using SCHEMA
        # Ensures the submitted template has the required information
        def self.validate(template)
            return false unless template.key?('FAAS')
            return false unless template['FAAS'].key?('FLAVOUR')
            return false unless template.key?('DEVICE_INFO')

            true
        end

        def self.to_service(client, specification)
            mapping_rules = client.conf[:mapping]

            faas = specification['FAAS']
            daas = specification['DAAS'] # optional

            tuple = faas['FLAVOUR']
            tuple = "#{tuple}-#{daas['FLAVOUR']}" if daas
            tuple = tuple.to_sym

            if !mapping_rules.key?(tuple)
                msg = "Cannot find a valid service template for the specified flavours: #{tuple}"
                msg << "FaaS -> #{faas}"
                msg << "DaaS -> #{daas}" if daas
                msg << "Mapping rules #{mapping_rules}"

                return [422, msg]
            end

            id = mapping_rules[tuple]

            # TODO: Role VM custom: CPU, Memory, Disk Size
            options = {}

            response = client.service_template_instantiate(id, options)

            rc = response.code.to_i
            rb = JSON.parse(response.body)

            [rc, rb]
        end

        def self.xaas_template(client, role)
            xaas_template = {}
            xaas_template['ENDPOINT'] = client.conf[:oneflow_server]

            # VM might be missing from role info
            return xaas_template unless role['nodes']

            vm_info = role['nodes']['vm_info']['VM']
            vm_id = vm_info['ID']

            response = client.vm_get(vm_id)
            rc = response[0]
            rb = response[1]

            return response unless rc == 200

            vm = rb

            # consequential parameters
            xaas_template['VM_ID'] = vm_id
            xaas_template['STATE'] = vm.state_str

            # optional specification parameters
            xaas_template['CPU'] = vm['//TEMPLATE/CPU']
            xaas_template['MEMORY'] = vm['//TEMPLATE/MEMORY']
            xaas_template['DISK_SIZE'] = vm['//TEMPLATE/DISK/SIZE']

            xaas_template
        end

    end

end
