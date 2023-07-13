require 'opennebula'
require 'opennebula/oneflow_client'
require_relative 'configuration'
require_relative 'faas'

module ProvisionEngine

    #
    # Abstracts the OpenNebula client that issues API Calls to oned and oneflow
    #
    class CloudClient

        def initialize(credentials)
            @conf = ProvisionEngine::Configuration.new

            @client_oned = client_oned(credentials)
            @client_flow = client_flow(credentials)
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

        def function_get(id)
            OpenNebula::FaaS.new_with_id(id, @client_oned)
        end

        def function_create(template)
            xml = OpenNebula::FaaS.build_xml
            faas = OpenNebula::FaaS.new(xml, @client_oned)

            faas.allocate(template)
        end

        def function_update(id, template, options = { :append => false })
            faas = Function.get(id, @client_oned)
            faas.update(id, template, options[:append])
        end

        def function_delete(id)
            faas = Function.get(id)
            faas.delete(id)
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

        def client_oned(credentials)
            options = {
                :url => @conf[:oneflow_server],
                :username => credentials.split(':')[0],
                :password => credentials.split(':')[-1]
            }
            Service::Client.new(options)
        end

        def client_flow(credentials)
            OpenNebula::Client.new(credentials, @conf[:one_xmlrpc])
        end

        def log_init
            return unless @conf[:log] > 1

            puts "Using oned at #{@conf[:one_xmlrpc]}"
            puts "Using oneflow at #{@conf[:oneflow_server]}"
        end

    end

end
