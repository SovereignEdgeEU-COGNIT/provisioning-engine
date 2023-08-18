module ProvisionEngine

    #
    # Abstracts the OpenNebula client that issues API Calls to oned and oneflow
    #
    class CloudClient

        def self.map_error_oned(xmlrpc_errno)
            # ESUCCESS        = 0x0000
            # EAUTHENTICATION = 0x0100
            # EAUTHORIZATION  = 0x0200
            # ENO_EXISTS      = 0x0400
            # EACTION         = 0x0800
            # EXML_RPC_API    = 0x1000
            # EINTERNAL       = 0x2000
            # EALLOCATE       = 0x4000
            # ENOTDEFINED     = 0xF001
            # EXML_RPC_CALL   = 0xF002

            case xmlrpc_errno
            when OpenNebla::Error::EAUTHORIZATION
                403
            when OpenNebla::Error::ENO_EXISTS
                404
            else
                xmlrpc_errno
            end
        end

        def initialize(conf, auth)
            @conf = conf

            create_client_oned(auth, conf[:one_xmlrpc])
            create_client_oneflow(auth, conf[:oneflow_server])
        end

        def runtime_get(id)
            runtime = ServerlessRuntime.new_with_id(id, @client_oned)
            runtime.info

            if runtime.name.nil?
                return [404, 'Not found']
            end

            [0, runtime]
        end

        def runtime_create(specification)
            response = runtime_specification_to_service(specification)
            rc = response.code.to_i
            rb = JSON.parse(response.body)

            if rc != 201
                return [rc, rb]
            end

            if true
                runtime = { 'NAME' => 'Dummy Serverless Runtime' }
                return [201, runtime]
            end

            service = rb

            xml = ServerlessRuntime.build_xml
            runtime = ServerlessRuntime.new(xml, @client_oned)

            response = runtime.allocate(specification)

            if OpenNebula.is_error?(response)
                return [self.class.map_error_oned(response.errno), response.message]
            end

            runtime.info

            service = service_get(service['DOCUMENT']['ID'])
            runtime.add_service(service)

            runtime.info

            [0, runtime]
        end

        def runtime_update(id, template, options = { :append => false })
            runtime = ServerlessRuntime.get(id, @client_oned)
            runtime.update(template, options[:append])
        end

        def runtime_delete(id)
            runtime = ServerlessRuntime.new_with_id(id, @client_oned)
            runtime.info

            if runtime.name.nil?
                return [404, 'Not found']
            end

            service_id = runtime.template['service_id']

            response = service_delete(service_id)
            rc = response.code.to_i
            rb = JSON.parse(response.body)

            if rc != 204
                return [rc, rb]
            end

            response = runtime.delete

            if OpenNebula.is_error?(response)
                return [self.class.map_error_oned(response.errno), response.message]
            end

            [0, '']
        end

        def vm_get(id)
            OpenNebula::VirtualMachine.new_with_id(id, @client_oned)
        end

        def vm_poweroff(id, options = { :hard => false })
            vm = vm_get(id)
            vm.poweroff(options[:hard])
        end

        def vm_terminate(id, options = { :hard => false })
            vm = vm_get(id)
            vm.terminate(options[:hard])
        end

        def service_get(id)
            @client_flow.get("/service/#{id}")
        end

        def service_update(id, body)
            @client_flow.put("/service/#{id}", body)
        end

        def service_delete(id)
            @client_flow.delete("/service/#{id}")
        end

        def service_action(id, action, options = {})
            url = "/service/#{id}/action", body
            flow_element_action(url, action, options)
        end

        def service_role_action(id, role, action, options = {})
            url = "/service/#{id}/role/#{role}/action"
            flow_element_action(url, action, options)
        end

        def service_template_get(id)
            @client_flow.get("/service_template/#{id}")
        end

        def service_template_create(body)
            @client_flow.post(PATH, body)
        end

        def service_template_update(id, body)
            @client_flow.put("/service_template/#{id}", body)
        end

        def service_template_delete(id)
            @client_flow.delete("/service_template/#{id}")
        end

        def service_template_instantiate(id, options = {})
            action(id, 'instantiate', options)
        end

        def service_template_action(id, action, options = {})
            url = "/service_template/#{id}/action"
            flow_element_action(url, action, { :merge_template => options })
        end

        private

        # Translates a runtime specification into a service instantiation
        def runtime_specification_to_service(runtime_template)
            if !ServerlessRuntime.validate(runtime_template)
                message = 'Invalid Serverless Runtime specification'
                return [400, message]
            end

            mapping_rules = @conf[:mapping]

            # role0, mandatory
            faas = runtime_template['faas']
            # role1, optional
            daas = runtime_template['daas']

            id = 0
            options = {}

            # TODO: Create correct service template
            if false
                service_template = {}

                response = service_template_create(service_template.to_json)

                rc = response.code.to_i
                rb = JSON.parse(response.body)

                if rc != 201
                    return [rc, rb]
                end
            end

            response = service_template_instantiate(id, options)

            if false
                response = service_template_delete(id)

                rc = response.code.to_i
                rb = JSON.parse(response.body)

                if rc != 204
                    return [rc, rb]
                end
            end

            rc = response.code.to_i
            rb = JSON.parse(response.body)

            [rc, rb]
        end

        def flow_element_action(url, action, options = {})
            body = {
                :action => {
                    :perform => action
                }
            }

            if !options.empty?
                body[:action][:params] = options
            end

            @client_oneflow.post(url, body)
        end

        def create_client_oneflow(auth, endpoint)
            options = {
                :url => endpoint,
                :username => auth.split(':')[0],
                :password => auth.split(':')[-1]
            }
            @client_oneflow = Service::Client.new(options)
        end

        def create_client_oned(auth, endpoint)
            @client_oned = OpenNebula::Client.new(auth, endpoint)
        end

    end

end
