module ProvisionEngine

    #
    # Abstracts the OpenNebula client that issues API Calls to oned and oneflow
    #
    class CloudClient

        def self.map_error(xmlrpc_errno)
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
            when OpenNebla::EAUTHORIZATION
                403
            when OpenNebla::ENO_EXISTS
                404
            else
                -1
            end
        end

        def initialize(conf, auth)
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

        def runtime_create(template)
            xml = ServerlessRuntime.build_xml
            runtime = ServerlessRuntime.new(xml, @client_oned)

            rc = runtime.allocate(template)

            if OpenNebula.is_error?(rc)
                return [-1, rc.message]
            end

            # TODO: Map runtime specification to service_template_id and merge options
            service_options = {}
            service_template_id = 0

            response = service_template_instantiate(service_template_id, service_options)

            rc = response.code.to_i
            rb = JSON.parse(response.body)

            if rc != 201
                return [rc, rb]
            end

            runtime.add_service(rb)
            [0, runtime]
        end

        def runtime_update(id, template, options = { :append => false })
            runtime = ServerlessRuntime.get(id, @client_oned)
            runtime.update(id, template, options[:append])
        end

        def runtime_delete(id)
            runtime = ServerlessRuntime.new_with_id(id, @client_oned)
            runtime.info

            if runtime.name.nil?
                return [404, 'Not found']
            end

            response = runtime.delete

            if OpenNebula.is_error?(response)
                return [self.class.map_error(response.errno), response.message]
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

        def self.flow_element_action(url, action, options = {})
            body = {
                :action => {
                    :perform => action
                }
            }

            if !options.empty?
                body[:action][:params] = options
            end

            @client.post(url, body)
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
