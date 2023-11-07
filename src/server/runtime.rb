module ProvisionEngine

    #
    # Document that references a service running functions specified by a client
    #
    class ServerlessRuntime < OpenNebula::DocumentJSON

        SR = 'Serverless Runtime'.freeze
        CVMR = 'Custom VM Requirements'.freeze

        DOCUMENT_TYPE = 1337

        FUNCTION_STATES = ['PENDING', 'RUNNING', 'UPDATING', 'ERROR'].freeze
        FUNCTION_LCM_STATES = {
            FUNCTION_STATES[0] => [
                'LCM_INIT',
                'BOOT',
                'PROLOG',
                'BOOT_UNKNOWN',
                'BOOT_POWEROFF',
                'BOOT_SUSPENDED',
                'BOOT_STOPPED',
                'BOOT_UNDEPLOY',
                'PROLOG_UNDEPLOY',
                'CLEANUP_RESUBMIT'
            ],
            FUNCTION_STATES[1] => ['RUNNING'],
            FUNCTION_STATES[3] => [
                'FAILURE',
                'UNKNOWN',
                'BOOT_FAILURE',
                'BOOT_MIGRATE_FAILURE',
                'BOOT_UNDEPLOY_FAILURE',
                'BOOT_STOPPED_FAILURE',
                'PROLOG_FAILURE',
                'PROLOG_MIGRATE_FAILURE',
                'PROLOG_MIGRATE_POWEROFF_FAILURE',
                'PROLOG_MIGRATE_SUSPEND_FAILURE',
                'PROLOG_RESUME_FAILURE',
                'PROLOG_UNDEPLOY_FAILURE',
                'PROLOG_MIGRATE_UNKNOWN',
                'PROLOG_MIGRATE_UNKNOWN_FAILURE'
            ]
        }.freeze

        SCHEMA_SPECIFICATION = {
            :type => 'object',
            :properties => {
                :SERVERLESS_RUNTIME => {
                    :type => 'object',
                    :properties => {
                        :NAME => {
                            :type => 'string'
                        },
                        :ID => {
                            :type => 'integer'
                        },
                        :SERVICE_ID => {
                            :type => 'integer'
                        },
                        :FAAS => {
                            :type => 'object',
                            :properties => {
                                :FLAVOUR => {
                                    :type => 'string'
                                },
                                :CPU => {
                                    :type => 'number'
                                },
                                :VCPU => {
                                    :type => 'integer'
                                },
                                :MEMORY => {
                                    :type => 'integer'
                                },
                                :DISK_SIZE => {
                                    :type => 'integer'
                                },
                                :VM_ID => {
                                    :type => 'integer'
                                },
                                :STATE => {
                                    :type =>  'string',
                                    :enum => FUNCTION_STATES
                                },
                                :ENDPOINT => {
                                    'oneOf' => [
                                        {
                                            :type => 'string'
                                        },
                                        {
                                            :type => 'null'
                                        }
                                    ]
                                }
                            },
                            :required => ['FLAVOUR']
                        },
                        :DAAS => {
                            'oneOf' => [
                                {
                                    :type => 'object',
                                    :properties => {
                                        :FLAVOUR => {
                                            :type => 'string'
                                        },
                                        :CPU => {
                                            :type => 'number'
                                        },
                                        :VCPU => {
                                            :type => 'integer'
                                        },
                                        :MEMORY => {
                                            :type => 'integer'
                                        },
                                        :DISK_SIZE => {
                                            :type => 'integer'
                                        },
                                        :VM_ID => {
                                            :type => 'integer'
                                        },
                                        :STATE => {
                                            :type => 'string',
                                            :enum => FUNCTION_STATES
                                        },
                                        :ENDPOINT => {
                                            'oneOf' => [
                                                {
                                                    :type => 'string'
                                                },
                                                {
                                                    :type => 'null'
                                                }
                                            ]
                                        }
                                    },
                                    :required => ['FLAVOUR']
                                },
                                {
                                    :type =>  'null'
                                }
                            ]
                        },
                        :SCHEDULING => {
                            :type => 'object',
                            :properties => {
                                :POLICY => {
                                    :type => 'string'
                                },
                                :REQUIREMENTS => {
                                    :type => 'string'
                                }
                            }
                        },
                        :DEVICE_INFO => {
                            :type => 'object',
                            :properties => {
                                :LATENCY_TO_PE => {
                                    :type => 'integer'
                                },
                                :GEOGRAPHIC_LOCATION => {
                                    :type => 'string'
                                }
                            }
                        }
                    },
                    :required => ['FAAS']
                }
            }
        }.freeze

        attr_accessor :cclient, :body

        def self.create(client, specification)
            response = ServerlessRuntime.validate(specification)
            return [400, response[1]] unless response[0]

            specification = specification['SERVERLESS_RUNTIME']

            client.logger.info("Creating oneflow Service for #{SR}")

            response = ServerlessRuntime.to_service(client, specification)
            rc = response[0]
            rb = response[1]

            return [rc, rb] if rc != 201

            service_id = rb['DOCUMENT']['ID']

            client.logger.info("#{SR} Service #{service_id} created")

            ServerlessRuntime.service_sync(client, specification, service_id)

            client.logger.info("Allocating #{SR} Document")
            client.logger.debug(specification)

            xml = ServerlessRuntime.build_xml
            runtime = ServerlessRuntime.new(xml, client.client_oned)
            response = runtime.allocate(specification)

            if OpenNebula.is_error?(response)
                return [ProvisionEngine::CloudClient.map_error_oned(response.errno),
                        response.message]
            end

            client.logger.info("Created #{SR} Document")

            runtime.info

            [201, runtime]
        end

        def self.get(client, id)
            runtime = ServerlessRuntime.new_with_id(id, client.client_oned)
            runtime.info

            runtime.cclient = client

            # DocumentJSON.info doesn't have error code
            return [404, 'Document not found'] if runtime.name.nil?

            runtime.load_body
            service_id = runtime.body['SERVICE_ID']

            ServerlessRuntime.service_sync(client, runtime.body, service_id)
            runtime.update

            [200, runtime]
        end

        def delete
            cclient.logger.info("Deleting #{SR} Service")

            document = JSON.parse(to_json)

            service_id = document['DOCUMENT']['TEMPLATE']['BODY']['SERVICE_ID']
            response = cclient.service_delete(service_id)
            rc = response[0]
            rb = response[1]

            if rc != 204
                if rc == 404
                    cclient.logger.warning("Cannot find #{SR} Service")
                elsif rc == 500 && rb == 'Service cannot be undeployed in state: DEPLOYING'
                    rc = 423
                    rb = "#{SR} has not finished deployment"
                end
                return [rc, rb]
            end

            cclient.logger.info("Deleting #{SR} Document")
            response = super()

            if OpenNebula.is_error?(response)
                return [ProvisionEngine::CloudClient.map_error_oned(response.errno),
                        response.message]
            end

            cclient.logger.info("#{SR} Document deleted")

            [204, '']
        end

        #
        # Validates the Serverless Runtime specification using the distributed schema
        #
        # @param [Hash] specification a valid runtime specification parsed to a Hash
        #
        # @return [Array] [true,''] or [false, 'reason']
        #
        def self.validate(specification)
            begin
                JSON::Validator.validate!(SCHEMA_SPECIFICATION, specification)
                [true, '']
            rescue JSON::Schema::ValidationError => e
                [false, "Invalid #{SR} specification: #{e.message}"]
            end
        end

        #####################
        # Inherited Functions
        #####################

        # Service must have been created prior to allocating the document
        def allocate(specification)
            specification['registration_time'] = Integer(Time.now)

            if specification['NAME']
                name = specification['NAME']
            else
                name = "#{ServerlessRuntime.tuple(specification)}_#{SecureRandom.uuid}"
            end

            super(specification.to_json, name)
        end

        #################
        # Helpers
        #################

        #
        # Translates the Serverless Runtime document to the SCHEMA
        #
        # @return [Hash] Serverless Runtime definition
        #
        def to_sr
            load_body if @body.nil?

            runtime = {
                :SERVERLESS_RUNTIME => {
                    :NAME => name,
                    :ID => id
                }
            }
            rsr = runtime[:SERVERLESS_RUNTIME]

            rsr.merge!(@body)
            rsr.delete('registration_time')

            runtime
        end

        #
        # Updates Serverless Runtime Document specification based on the underlying elements state
        #
        # @param [CloudClient] client OpenNebula interface
        # @param [Hash] runtime_definition Serverless Runtime definition to be updated
        # @param [Integer] service_id OneFlow service ID mapped to the Serverless Runtime
        # @param [Integer] timeout How long to wait for Role VMs to be created
        #
        def self.service_sync(client, runtime_definition, service_id, timeout = 30)
            1.upto(timeout) do |t|
                sleep 1

                if t == 30
                    msg = "OpenNebula did not create VMs for the #{SR} service after #{t} seconds"
                    return [504, msg]
                end

                response = client.service_get(service_id)
                rc = response[0]
                rb = response[1]

                return [rc, rb] if rc != 200

                service = rb

                service_template = service['DOCUMENT']['TEMPLATE']['BODY']
                roles = service_template['roles']

                begin
                    roles[0]['nodes'][0]['vm_info']['VM']
                rescue NoMethodError # will fail if service VM information is missing
                    client.logger.debug("Waiting #{t} seconds for service VMs")

                    next
                end

                client.logger.debug(service)

                runtime_definition['SERVICE_ID'] = service['DOCUMENT']['ID'].to_i
                runtime_definition['FAAS'].merge!(xaas_template(client, roles[0]))
                runtime_definition['DAAS'].merge!(xaas_template(client, roles[1])) if roles[1]

                break
            end
        end

        #
        # Create oneflow service based on Serverless Runtime specification
        #
        # @param [CloudClient] OpenNebula interface
        # @param [Hash] specification Serverless Runtime specification
        #
        # @return [Array] Response Code and Body of the operation
        #
        def self.to_service(client, specification)
            response = client.service_template_pool_get
            rc = response[0]

            return response if rc != 200

            if response[1]['DOCUMENT_POOL'].empty?
                msg = "User requesting #{SR} creation has no flow templates available for use"
                return [403, msg]
            end

            service_templates = response[1]['DOCUMENT_POOL']['DOCUMENT']

            tuple = ServerlessRuntime.tuple(specification)

            # find flow_template matching flavour tuple
            service_templates.each do |service_template|
                service_template_body = service_template['TEMPLATE']['BODY']
                next unless service_template_body['name'] == tuple

                merge_template = {
                    'roles' => []
                }

                schevice=''
                ['SCHEDULING', 'DEVICE_INFO'].each do |i|
                    next unless specification.key?(i)

                    i_template = ''
                    specification[i].each do |property, value|
                        i_template << "#{property}=\"#{value}\",\n" if value
                    end

                    if !i_template.empty?
                        i_template.reverse!.sub!("\n", '').reverse!
                        i_template.reverse!.sub!(',', '').reverse!
                    end

                    schevice << "#{i}=[#{i_template}]\n"
                end

                ['FAAS', 'DAAS'].each do |role|
                    next unless specification[role]

                    client.logger.info("Requesting #{CVMR} for function #{role}\n#{specification[role]}")

                    service_template_body['roles'].each do |service_template_role|
                        next unless service_template_role['name'] == role

                        response = client.vm_template_get(service_template_role['vm_template'])

                        if response[0] != 200
                            client.logger.error("Failed to establish #{CVMR} for #{role}")
                            return response
                        end

                        override = function_requierements(specification[role], response[1],
                                                          client.conf[:capacity])

                        client.logger.debug("Applying vm_template_contents to role #{role}\n#{override}")
                        merge_template['roles'] << {
                            'name' => role,
                            'vm_template_contents' => "#{override}\n#{schevice}"
                        }
                    end
                end

                return client.service_template_instantiate(service_template['ID'], merge_template)
            end

            msg = "Cannot find a valid service template for the specified flavours: #{tuple}\n"
            msg << "FaaS -> #{specification['FAAS']}"
            msg << "DaaS -> #{specification['DAAS']}" if specification['DAAS']

            return [422, msg]
        end

        def self.tuple(specification)
            tuple = specification['FAAS']['FLAVOUR']
            tuple = "#{tuple}-#{specification['DAAS']['FLAVOUR']}" if specification['DAAS']
            tuple
        end

        #
        # Creates a runtime function hash for the Serverless Runtime document
        #
        # @param [CloudClient] OpenNebula interface
        # @param [Hash] role oneflow service role information
        #
        # @return [Hash] Function hash
        #
        def self.xaas_template(client, role)
            vm_info = role['nodes'][0]['vm_info']['VM']
            vm_id = vm_info['ID'].to_i

            response = client.vm_get(vm_id)
            rc = response[0]
            rb = response[1]

            return response unless rc == 200

            vm = rb
            xaas_template = {}
            t = '//TEMPLATE/'
            nic = "#{t}NIC[NIC_ID=\"0\"]/"

            xaas_template['VM_ID'] = vm_id
            xaas_template['STATE'] = map_vm_state(vm)

            if vm["#{nic}EXTERNAL_IP"]
                xaas_template['ENDPOINT'] = vm["#{nic}EXTERNAL_IP"]
            else
                xaas_template['ENDPOINT'] = vm["#{nic}IP"]
            end

            xaas_template['CPU'] = vm["#{t}CPU"].to_f
            xaas_template['VCPU'] = vm["#{t}VCPU"].to_i
            xaas_template['MEMORY'] = vm["#{t}MEMORY"].to_i
            xaas_template['DISK_SIZE'] = vm["#{t}DISK[DISK_ID=\"0\"]/SIZE"].to_i

            xaas_template
        end

        #
        # Creates information compatible with oneflow vm_template contents for a given
        # role in a Serverless Runtime specification
        #
        # @param [Hash] specification Function specification found in Serverless Runtime definition
        # @param [OpenNebula::Template] vm_template Function baseline VM template
        # @param [Hash] conf_capacity Engine configuration attribute for max capacity assumptions
        #
        # @return [String] vm_template contents for a oneflow service template
        #
        def self.function_requierements(role_specification, vm_template, conf_capacity)
            disk_size = role_specification['DISK_SIZE']
            xaas = []

            xaas << "CPU=#{role_specification['CPU']}" if role_specification['CPU']
            xaas << "HOT_RESIZE=[CPU_HOT_ADD_ENABLED=\"YES\",\nMEMORY_HOT_ADD_ENABLED=\"YES\"]"
            xaas << 'MEMORY_RESIZE_MODE="BALLOONING"'

            if disk_size
                disk_template = vm_template.template_like_str('//TEMPLATE/DISK')

                if disk_template.include?('SIZE=')
                    disk_template.sub!("SIZE=\d+", "SIZE=\"#{disk_size}\"")
                else
                    disk_template << "\n#{"SIZE=\"#{disk_size}\""}"
                end

                disk_template.gsub!(/"$/, '",').reverse!.sub!(',', '').reverse!
                xaas << "DISK=[#{disk_template}]"
            end

            if role_specification['VCPU']
                xaas << "VCPU=#{role_specification['VCPU']}"

                vcpu_max = role_specification['VCPU'] * conf_capacity[:max][:vcpu_mult]
            else # get upper limit from mult * vm_template_vcpu
                vcpu = vm_template['//TEMPLATE/VCPU'].to_i
                vcpu = conf_capacity[:default][:vcpu] if vcpu.zero?

                vcpu_max = vcpu * conf_capacity[:max][:vcpu_mult]
            end
            if role_specification['MEMORY']
                xaas << "MEMORY=#{role_specification['MEMORY']}"

                memory_max = role_specification['MEMORY'] * conf_capacity[:max][:memory_mult]
            else # get upper limit from mult * vm_template_memory
                memory = vm_template['//TEMPLATE/MEMORY'].to_i
                memory = conf_capacity[:default][:memory] if memory.zero?

                memory_max = memory * conf_capacity[:max][:memory_mult]
            end

            xaas << "VCPU_MAX= \"#{vcpu_max}\""
            xaas << "MEMORY_MAX=\"#{memory_max}\""

            xaas.join("\n")
        end

        #
        # Maps an OpenNebula VM state to the accepted Function VM states
        #
        # @param [OpenNebula::VirtualMachine] vm Virtual Machine representing the Function
        #
        # @return [String] Serverless Runtime Function state
        #
        def self.map_vm_state(vm)
            case vm.state_str
            when 'INIT', 'PENDING', 'HOLD'
                return FUNCTION_STATES[0]
            when 'ACTIVE'
                FUNCTION_LCM_STATES.each do |function_state, vm_states|
                    return function_state if vm_states.include?(vm.lcm_state_str)
                end
            when 'STOPPED', 'SUSPENDED', 'POWEROFF', 'UNDEPLOYED', 'CLONING'
                return FUNCTION_STATES[2]
            else
                return FUNCTION_STATES[3]
            end
        end

    end

end
