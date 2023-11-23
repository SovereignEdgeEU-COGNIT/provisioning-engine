module ProvisionEngine

    #
    # Abstracts the OpenNebula client that issues API Calls to oned and oneflow
    #
    class CloudClient

        attr_accessor :conf, :client_oned, :client_oneflow, :logger

        def initialize(conf, auth)
            @conf = conf
            @logger = ProvisionEngine::Logger.new(conf[:log], 'CloudClient')

            create_client_oned(auth, conf[:one_xmlrpc])
            create_client_oneflow(auth, conf[:oneflow_server])
        end

        #############
        # oned
        #############

        def vm_get(id)
            id = id.to_i unless id.is_a?(Integer)
            vm = OpenNebula::VirtualMachine.new_with_id(id, @client_oned)

            response = vm.info
            if OpenNebula.is_error?(response)
                rc = ProvisionEngine::Error.map_error_oned(response.errno)
                return [rc, response.message]
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

        def vm_template_get(id)
            template = OpenNebula::Template.new_with_id(id, @client_oned)

            response = template.info
            if OpenNebula.is_error?(response)
                rc = ProvisionEngine::Error.map_error_oned(response.errno)
                return [rc, response.message]
            end

            [200, template]
        end

        #############
        # oneflow
        #############

        def service_get(id)
            response = @client_oneflow.get("/service/#{id}")
            return_http_response(response)
        end

        def service_update(id, body)
            @logger.info("Updating service #{id}")
            @logger.debug(body)

            response = @client_oneflow.put("/service/#{id}", body)
            return_http_response(response)
        end

        def service_delete(id)
            @logger.info("Deleting service #{id}")

            response = @client_oneflow.delete("/service/#{id}")
            return_http_response(response)
        end

        def service_destroy(id)
            service_recover(id, { 'delete' => true })
        end

        def service_recover(id, options = {})
            if options['delete']
                @logger.info("Forcing service #{id} deletion")
            else
                @logger.info("Recovering service #{id} deletion")
            end

            response = service_action(id, 'recover', options)
            return_http_response(response)
        end

        def service_fail?(service)
            OpenNebula::Service::STATE_STR[service_state(service)].include?('FAILED')
        end

        def service_state(service)
            service['DOCUMENT']['TEMPLATE']['BODY']['state']
        end

        def service_pool_get
            response = @client_oneflow.get('/service')
            return_http_response(response)
        end

        def service_template_get(id)
            response = @client_oneflow.get("/service_template/#{id}")
            return_http_response(response)
        end

        def service_template_instantiate(id, options = {})
            @logger.info("Instantiating service_template #{id}")

            response = service_template_action(id, 'instantiate', options)
            return_http_response(response)
        end

        def service_template_pool_get
            response = @client_oneflow.get('/service_template')
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
            url = "/service/#{id}/action"

            flow_element_action(url, action, options)
        end

        def service_role_action(id, role, action, options = {})
            url = "/service/#{id}/role/#{role}/action"

            flow_element_action(url, action, options)
        end

        def flow_element_action(url, action, options = {})
            body = Service.build_json_action(action, options)

            if !options.empty?
                @logger.info('with additional parameters')
                @logger.debug(options)
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
