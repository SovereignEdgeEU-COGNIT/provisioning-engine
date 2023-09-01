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

        attr_accessor :conf, :client_oned, :client_oneflow, :logger

        #############
        # oned
        #############

        def initialize(conf, auth)
            @conf = conf
            @logger = ProvisionEngine::Logger.new(conf[:log], 'CloudClient')

            create_client_oned(auth, conf[:one_xmlrpc])
            create_client_oneflow(auth, conf[:oneflow_server])
        end

        def vm_get(id)
            vm = OpenNebula::VirtualMachine.new_with_id(id, @client_oned)

            response = vm.info
            if OpenNebula.is_error?(response)
                return [ProvisionEngine::CloudClient.map_error_oned(response.errno),
                        response.message]
            end

            [200, vm]
        end

        def vm_poweroff(id, options = { :hard => false })
            response = vm_get(id)
            rc = response[0]
            return response unless rc == 200

            vm = response[1]
            vm.poweroff(options[:hard])
        end

        def vm_terminate(id, options = { :hard => false })
            response = vm_get(id)
            rc = response[0]
            return response unless rc == 200

            vm = response[1]
            vm.terminate(options[:hard])
        end

        #############
        # oneflow
        #############

        def service_get(id)
            response = @client_oneflow.get("/service/#{id}")
            return_http_response(response)
        end

        def service_update(id, body)
            @logger.debug("Updating service #{id} with #{body}")

            response = @client_oneflow.put("/service/#{id}", body)
            return_http_response(response)
        end

        def service_delete(id)
            @logger.debug("Deleting service #{id}")

            response = @client_oneflow.delete("/service/#{id}")
            return_http_response(response)
        end

        def service_template_get(id)
            response = @client_oneflow.get("/service_template/#{id}")
            return_http_response(response)
        end

        def service_template_instantiate(id, options = {})
            @logger.debug("Instantiating service_template #{id} with options #{options}")

            response = service_template_action(id, 'instantiate', options)
            return_http_response(response)
        end

        private

        def return_http_response(response)
            if response.instance_variable_defined?(:@body) && response.body
                body = JSON.parse(response.body)
            elsif response.instance_variable_defined?(:@message) && response.message
                body = response.message
            else
                body = ''
            end

            [response.code.to_i, body]
        end

        def service_template_action(id, action, options = {})
            url = "/service_template/#{id}/action"
            options = { :merge_template => options } unless options.empty?

            flow_element_action(url, action, options)
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
