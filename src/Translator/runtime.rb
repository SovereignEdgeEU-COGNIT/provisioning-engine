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
            rc = response.code.to_i
            rb = JSON.parse(response.body)

            if rc != 201
                return [rc, rb]
            end

            service = rb

            # Create document from specification + created service state

            specification['SERVICE_ID'] = service['DOCUMENT']['ID']

            service_template = service['DOCUMENT']['TEMPLATE']['BODY']
            roles = service_template['roles']

            specification['FAAS'].merge!(add_xass(client, roles[0]))
            specification['DAAS'].merge!(add_xass(client, roles[1])) if roles[1]

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
        def self.update(client, id, changes, options = { :append => false })
            runtime = ServerlessRuntime.new_with_id(client, id)
            runtime.info

            return [404, 'Document not found'] if runtime.name.nil?

            # Update VMs ?

            # Update service

            # Update document

            runtime.update(changes, options[:append])

            [200, runtime]
        end

        def self.delete(client, id)
            runtime = ServerlessRuntime.new_with_id(client, id)
            runtime.info

            return [404, 'Document not found'] if runtime.name.nil?

            runtime.load_body
            service_id = runtime.body['DOCUMENT']['TEMPLATE']['BODY']['SERVICE_ID']

            response = client.service_delete(service_id)
            rc = response.code.to_i
            rb = JSON.parse(response.body)

            if rc != 204
                return [rc, rb]
            end

            response = runtime.delete

            if OpenNebula.is_error?(response)
                return [self.class.map_error_oned(response.errno), response.message]
            end

            [204, '']
        end

        # Child Functions

        # Service must have been created prior to allocating the document
        def allocate(specification)
            specification['registration_time'] = Integer(Time.now)

            super(specification.to_json, specification['NAME'])
        end

        # Helpers

        # TODO: Validate using SCHEMA
        # Ensures the submitted template has the required information
        def self.validate(template)
            return false unless template.key?('FAAS')
            return false unless template['FASS'].key?('FLAVOUR')

            return false unless template.key?('DEVICE_INFO')
            return false unless template.key?('LATENCY_TO_PE')
            return false unless template.key?('GEOGRAPHIC_LOCATION')

            true
        end

        def self.to_service(client, specification)
            mapping_rules = client.conf[:mapping]

            faas = specification['faas']
            daas = specification['daas'] # optional

            tuple = faas['FLAVOUR']
            tuple = "#{tuple}-#{daas['FLAVOUR']}" if daas
            tuple = tuple.to_sym

            # TODO: Consider mapping tuples not required config wise
            # instead do a template lookup and match by name
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

        def add_xass(client, role_info)
            vm_info = role_info['nodes']['vm_info']['VM']

            vm_id = vm_info['ID']
            client.vm_get(vm)

            xaas_template = {}

            xaas_template['vm_id'] = vm_id
            xaas_template['cpu']
            xaas_template['memory']
            xaas_template['disk_size']
            xaas_template['flavour']
            xaas_template['endpoint']
            xaas_template['state']

            xaas_template
        end

    end

end
