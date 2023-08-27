module ProvisionEngine

    # Serverless runtime class as wrapper of DocumentJSON
    class ServerlessRuntime < OpenNebula::DocumentJSON

        DOCUMENT_TYPE = 1337

        def self.create(client, specification)
            if !ServerlessRuntime.validate(specification)
                message = 'Invalid Serverless Runtime specification'
                return [400, message]
            end

            client.logger.info('Creating oneflow Service for Serverless Runtime')

            response = ServerlessRuntime.to_service(client, specification)
            rc = response[0]
            rb = response[1]

            return [rc, rb] if rc != 201

            client.logger.info('Serverless Runtime Service created')

            # When the service instantiates it has no running VMs
            response = client.service_get(rb['DOCUMENT']['ID'])
            rc = response[0]
            rb = response[1]

            return [rc, rb] if rc != 200

            service = rb

            client.logger.debug(service)
            client.logger.info('Allocating Serverless Runtime Document')

            specification['SERVICE_ID'] = service['DOCUMENT']['ID']

            service_template = service['DOCUMENT']['TEMPLATE']['BODY']
            roles = service_template['roles']

            specification['FAAS'].merge!(xaas_template(client, roles[0]))
            specification['DAAS'].merge!(xaas_template(client, roles[1])) if roles[1]

            client.logger.debug(specification)

            xml = ServerlessRuntime.build_xml
            runtime = ServerlessRuntime.new(xml, client.client_oned)
            response = runtime.allocate(specification)

            if OpenNebula.is_error?(response)
                return [ProvisionEngine::CloudClient.map_error_oned(response.errno), response.message]
            end

            client.logger.info('Created Serverless Runtime Document')

            runtime.info

            [201, runtime]
        end

        def self.get(client, id)
            runtime = ServerlessRuntime.new_with_id(client.client_oned, id)
            runtime.info

            return [404, 'Document not found'] if runtime.name.nil?

            runtime.load_body

            [200, runtime]
        end

        # TODO
        def update(client, id, changes, options = { :append => false })
            runtime = ServerlessRuntime.new_with_id(client.client_oned, id)
            runtime.info

            return [404, 'Document not found'] if runtime.name.nil?

            # Update VMs ?

            # Update service

            # Update document

            runtime.update(changes, options[:append])

            [200, runtime]
        end

        def delete(client, id)
            runtime = ServerlessRuntime.get(client, id)

            client.logger.info('Deleting Serverless Runtime Service')

            service_id = runtime.body['DOCUMENT']['TEMPLATE']['BODY']['SERVICE_ID']
            response = client.service_delete(service_id)
            rc = response[0]

            if rc == 404
                client.logger.warn('Cannot find Serverless Runtime Service')
            elsif rc != 204
                rb = response[1]
                return [rc, rb]
            end

            client.logger.info('Deleting Serverless Runtime Document')
            response = runtime.delete

            if OpenNebula.is_error?(response)
                return [ProvisionEngine::CloudClient.map_error_oned(response.errno), response.message]
            end

            client.logger.info('Serverless Runtime Document deleted')

            [204, '']
        end

        #####################
        # Inherited Functions
        #####################

        # Service must have been created prior to allocating the document
        def allocate(specification)
            specification['registration_time'] = Integer(Time.now)

            super(specification, specification['NAME'])
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

            client.service_template_instantiate(id, options)
        end

        def self.xaas_template(client, role)
            xaas_template = {}
            xaas_template['ENDPOINT'] = client.conf[:oneflow_server]

            # VM might be missing from role info
            return xaas_template unless role['nodes']

            vm_info = role['nodes'][0]['vm_info']['VM']
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
