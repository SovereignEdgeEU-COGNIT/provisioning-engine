module ProvisionEngine

    # Serverless runtime class as wrapper of DocumentJSON
    class ServerlessRuntime < OpenNebula::DocumentJSON

        DOCUMENT_TYPE = 1337

        # Service must have been created prior to allocating the document
        def allocate(specification)
            specification['registration_time'] = Integer(Time.now)

            super(specification.to_json, specification['NAME'])
        end

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

        # Updates the document xml with instatianted service information
        def add_service(service)
            new_template = {}

            service_template = service['DOCUMENT']['TEMPLATE']['BODY']
            new_template['SERVICE_ID'] = service['DOCUMENT']['ID']

            roles = service_template['roles']

            add_xass('faas', roles[0])
            return unless roles[1]

            add_xass('daas', roles[1])

            update(new_template)
        end

        def add_xass(xass, _role_info)
            xaas_template = {}

            xaas_template['cpu']
            xaas_template['memory']
            xaas_template['disk_size']
            xaas_template['flavour']
            xaas_template['endpoint']
            xaas_template['state']
            xaas_template['vm_id']

            xaas_template
        end

    end

end
