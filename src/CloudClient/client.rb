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

        attr_accessor :conf

        def initialize(conf, auth)
            @conf = conf

            create_client_oned(auth, conf[:one_xmlrpc])
            create_client_oneflow(auth, conf[:oneflow_server])
        end

        def vm_get(id)
            vm = OpenNebula::VirtualMachine.new_with_id(id, @client_oned)
            vm.info
            vm
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
            service_template_action(id, 'instantiate', options)
        end

        private

        def service_template_action(id, action, options = {})
            url = "/service_template/#{id}/action"
            options = { :merge_template => options } unless options.empty?

            flow_element_action(url, action, { :merge_template => options })
        end

        def service_action(id, action, options = {})
            url = "/service/#{id}/action", body

            flow_element_action(url, action, options)
        end

        def service_role_action(id, role, action, options = {})
            url = "/service/#{id}/role/#{role}/action"

            flow_element_action(url, action, options)
        end

        def flow_element_action(url, action, options = {})
            body = Service.build_json_action(action, options)

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
