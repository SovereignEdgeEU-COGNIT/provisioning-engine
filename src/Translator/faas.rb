module OpenNebula

    # Serverless runtime class as wrapper of DocumentJSON
    class FaaS < DocumentJSON

        DOCUMENT_TYPE = 1337

        def allocate(template)
            template = JSON.parse(template)
            FaaS.validate(template)

            template['registration_time'] = Integer(Time.now)

            super(template.to_json, template['name'])
        end

        # Ensures the submitted template is valid
        def self.validate(template); end

    end

end
