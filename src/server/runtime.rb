module ProvisionEngine

    # Serverless runtime class as wrapper of DocumentJSON
    class ServerlessRuntime < OpenNebula::DocumentJSON

        DOCUMENT_TYPE = 1337

        SCHEMA_SPECIFICATION = {
            :type => 'object',
            :properties => {
                :SERVERLESS_RUNTIME => {
                    :type => 'object',
                :properties => {
                    :NAME => {
                        :type => 'string'
                    },
                    :FAAS => {
                        :type => 'object',
                    :properties => {
                        :CPU => {
                            :type => 'integer'
                        },
                        :MEMORY => {
                            :type => 'integer'
                        },
                        :DISK_SIZE => {
                            :type => 'integer'
                        },
                        :FLAVOUR => {
                            :type => 'string'
                        }
                    },
                    :required => ['FLAVOUR']
                    },
                    :DAAS => {
                        :type => 'object',
                    :properties => {
                        :CPU => {
                            :type => 'integer'
                        },
                        :MEMORY => {
                            :type => 'integer'
                        },
                        :DISK_SIZE => {
                            :type => 'integer'
                        },
                        :FLAVOUR => {
                            :type => 'string'
                        }
                    },
                    :required => ['FLAVOUR']
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
        }

        def self.create(client, specification)
            response = ServerlessRuntime.validate(specification)
            return [400, response[1]] unless response[0]

            specification = specification['SERVERLESS_RUNTIME']

            client.logger.info('Creating oneflow Service for Serverless Runtime')

            response = ServerlessRuntime.to_service(client, specification)
            rc = response[0]
            rb = response[1]

            return [rc, rb] if rc != 201

            client.logger.info('Serverless Runtime Service created')

            # When the service instantiates it has no associated VMs
            response = client.service_get(rb['DOCUMENT']['ID'])
            rc = response[0]
            rb = response[1]

            return [rc, rb] if rc != 200

            service = rb

            client.logger.debug(service)
            client.logger.info('Allocating Serverless Runtime Document')

            specification['SERVICE_ID'] = service['DOCUMENT']['ID']

            service_template = service['DOCUMENT']['TEMPLATE']['BODY']
            roles = service_template['roles']

            specification['FAAS'].merge!(xaas_template(client, roles[0]))
            specification['DAAS'].merge!(xaas_template(client, roles[1])) if roles[1]

            client.logger.debug(specification)

            xml = ServerlessRuntime.build_xml
            runtime = ServerlessRuntime.new(xml, client.client_oned)
            response = runtime.allocate(specification)

            if OpenNebula.is_error?(response)
                return [ProvisionEngine::CloudClient.map_error_oned(response.errno),
                        response.message]
            end

            client.logger.info('Created Serverless Runtime Document')

            runtime.info
            [201, runtime]
        end

        def self.get(client, id)
            runtime = ServerlessRuntime.new_with_id(id, client.client_oned)
            runtime.info

            # TODO: Update runtime object with latest service and VM states/information ?

            return [404, 'Document not found'] if runtime.name.nil?

            [200, runtime]
        end

        # TODO
        def update(client, id, changes, options = { :append => false })
            runtime = ServerlessRuntime.new_with_id(id, client.client_oned)
            runtime.info

            return [404, 'Document not found'] if runtime.name.nil?

            # Update VMs ?

            # Update service

            # Update document

            runtime.update(changes, options[:append])

            [200, runtime]
        end

        # TODO: Extend initialization to keep cloud_client access within the object
        def delete(client)
            client.logger.info('Deleting Serverless Runtime Service')

            document = JSON.parse(to_json)

            service_id = document['DOCUMENT']['TEMPLATE']['BODY']['SERVICE_ID']
            response = client.service_delete(service_id)
            rc = response[0]

            if rc == 404
                client.logger.warning('Cannot find Serverless Runtime Service')
            elsif rc != 204
                rb = response[1]
                return [rc, rb]
            end

            client.logger.info('Deleting Serverless Runtime Document')
            response = super()

            if OpenNebula.is_error?(response)
                return [ProvisionEngine::CloudClient.map_error_oned(response.errno),
                        response.message]
            end

            client.logger.info('Serverless Runtime Document deleted')

            [204, '']
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
                [false, "Invalid Serverless Runtime specification: #{e.message}"]
            end
        end

        def self.to_service(client, specification)
            mapping_rules = client.conf[:mapping]

            tuple = ServerlessRuntime.tuple(specification)

            if !mapping_rules.key?(tuple)
                msg = "Cannot find a valid service template for the specified flavours: #{tuple}"
                msg << "FaaS -> #{specification['FAAS']}"
                msg << "DaaS -> #{specification['DAAS']}" if specification['DAAS']
                msg << "Mapping rules #{mapping_rules}"

                return [422, msg]
            end

            id = mapping_rules[tuple]

            client.service_template_instantiate(id)
        end

        def self.tuple(specification)
            tuple = specification['FAAS']['FLAVOUR']
            tuple = "#{tuple}-#{specification['DAAS']['FLAVOUR']}" if specification['DAAS']
            tuple.to_sym
        end

        def self.xaas_template(client, role)
            xaas_template = {}
            xaas_template['ENDPOINT'] = client.conf[:oneflow_server]

            # VM might be missing from role info
            return xaas_template unless role['nodes']

            vm_info = role['nodes'][0]['vm_info']['VM']
            vm_id = vm_info['ID']

            response = client.vm_get(vm_id)
            rc = response[0]
            rb = response[1]

            return response unless rc == 200

            vm = rb

            # consequential parameters
            xaas_template['VM_ID'] = vm_id
            xaas_template['STATE'] = vm.state_str

            # optional specification parameters
            xaas_template['CPU'] = vm['//TEMPLATE/CPU']
            xaas_template['MEMORY'] = vm['//TEMPLATE/MEMORY']
            xaas_template['DISK_SIZE'] = vm['//TEMPLATE/DISK/SIZE']

            xaas_template
        end

    end

end
