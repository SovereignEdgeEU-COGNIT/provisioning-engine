module ProvisionEngine

    # Serverless runtime class as wrapper of DocumentJSON
    class ServerlessRuntime < OpenNebula::DocumentJSON

        DOCUMENT_TYPE = 1337

        def allocate(template_json)
            template = JSON.parse(template_json)

            self.class.valid_definition?(template)

            template['registration_time'] = Integer(Time.now)

            super(template_json, template['name'])
        end

        # TODO
        # Ensures the submitted template is valid
        def self.valid_definition?(template)
            return false unless template

            true
        end

        # Updates the document xml with instatianted service information
        def add_service(service_json)
            template['service_id'] = service_json['ID']

            roles = service_json['roles']

            add_xass('faas', roles[0])
            return unless roles[1]

            add_xass('daas', roles[1])
        end

        def add_xass(xass, _role_info)
            new_template = {}

            new_template['cpu']
            new_template['memory']
            new_template['disk_size']
            new_template['flavour']
            new_template['endpoint']
            new_template['state']
            new_template['vm_id']

            template[xass].merge(new_template)
        end

    end

end
