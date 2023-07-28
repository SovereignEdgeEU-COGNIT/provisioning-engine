module ProvisionEngine

    # Serverless runtime class as wrapper of DocumentJSON
    class ServerlessRuntime < OpenNebula::DocumentJSON

        DOCUMENT_TYPE = 1337

        def allocate(template)
            template = JSON.parse(template)
            FaaS.valid_definition?(template)

            template['registration_time'] = Integer(Time.now)

            super(template.to_json, template['name'])
        end

        # Ensures the submitted template is valid
        def self.valid_definition?(template)
            return false unless template

            true
        end

    end

end
