module ProvisionEngine

    #
    # Abstracts the OpenNebula client that issues API Calls to oned and oneflow
    #
    class CloudClient

        def initialize(conf, auth)
            @client_oned = client_oned(conf[:one_xmlrpc], auth)
            @client_oned = client_oneflow(conf[:oneflow_server], auth)
        end

        def runtime_get(id)
            ServerlessRuntime.new_with_id(id, @client_oned)
        end

        def runtime_create(template)
            xml = ServerlessRuntime.build_xml
            runtime = ServerlessRuntime.new(xml, @client_oned)

            runtime.allocate(template)
        end

        def runtime_update(id, template, options = { :append => false })
            runtime = ServerlessRuntime.get(id, @client_oned)
            runtime.update(id, template, options[:append])
        end

        def runtime_delete(id)
            runtime = ServerlessRuntime.get(id)
            runtime.delete(id)
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

        def client_oned(endpoint, auth)
            options = {
                :url => endpoint,
                :username => auth.split(':')[0],
                :password => auth.split(':')[-1]
            }
            Service::Client.new(options)
        end

        def client_flow(endpoint, auth)
            OpenNebula::Client.new(endpoint, auth)
        end

    end

end
