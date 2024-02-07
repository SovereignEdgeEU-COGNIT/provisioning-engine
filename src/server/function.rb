module ProvisionEngine

    #
    # Virtual Machine backing a Serverless Runtime Function as a Service
    #
    class Function < OpenNebula::VirtualMachine

        STATES = {
            :pending  => 'PENDING',
            :running  => 'RUNNING',
            :error    => 'ERROR',
            :updating => 'UPDATING'
        }.freeze
        STATE_MAP = {
            STATES[:pending] => [
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
            STATES[:running] => ['RUNNING'],
            STATES[:error] => [
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
        SCHED_MAP = {
            'REQUIREMENTS' => 'SCHED_REQUIREMENTS',
            'POLICY' => 'SCHED_RANK'
        }
        FUNCTIONS = ['FAAS', 'DAAS'].freeze

        T = '//TEMPLATE/'.freeze
        UT = '//USER_TEMPLATE/'.freeze
        NIC = "#{T}NIC[NIC_ID=\"0\"]".freeze
        SRF = 'Serverless Runtime Function VM'.freeze

        def id
            @pe_id.to_i
        end

        def memory
            {
                :memory => self["#{T}/MEMORY"].to_i,
                :resize => {
                    :enabled => self["#{UT}MEMORY_HOT_ADD_ENABLED"],
                    :mode => self["#{T}/MEMORY_RESIZE_MODE"],
                    :limit => self["#{T}/MEMORY_MAX"].to_i
                }

            }
        end

        def cpu
            {
                :cpu => self["#{T}/CPU"].to_f,
                :vcpu => self["#{T}/VCPU"].to_i,
                :resize => {
                    :enabled => self["#{UT}CPU_HOT_ADD_ENABLED"],
                    :limit => self["#{T}/VCPU_MAX"].to_i
                }
            }
        end

        def size
            self["#{T}DISK[DISK_ID=\"0\"]/SIZE"].to_i
        end

        def error
            self["#{T}ERROR"]
        end

        def report_ready?
            self["#{T}/CONTEXT/REPORT_READY"] == 'YES'
        end

        def ready?
            self["#{UT}READY"] == 'YES'
        end

        #
        # Establishes the endpoint exposed to the device client
        #
        # @return [String] Address
        #
        def endpoint
            return '' unless self[NIC]

            ['EXTERNAL_IP', 'IP6', 'IP'].each do |address|
                return self["#{NIC}/#{address}"] if self["#{NIC}/#{address}"]
            end

            return ''
        end

        #
        # Loads Serverless Runtime Function as a Service Virtual Machine
        #
        # @param [OpenNebula::Client] client oned interface
        # @param [Int] id VM ID of the VM backing a Function
        #
        # @return [Array] [Response Code, Function Virtual Machine/Error]
        #
        def self.get(client, id)
            id = id.to_i unless id.is_a?(Integer)
            vm = ProvisionEngine::Function.new_with_id(id, client)

            response = vm.info
            if OpenNebula.is_error?(response)
                rc = ProvisionEngine::Error.map_error_oned(response.errno)
                error = "Failed to read #{SRF}"
                return ProvisionEngine::Error.new(rc, error, response.error)
            end

            [200, vm]
        end

        #
        # Generates oneflow service vm_template_contents for a given role
        # based on a Serverless Runtime Function specification
        #
        # @param [Hash] specification Function specification found in Serverless Runtime definition
        # @param [OpenNebula::Template] vm_template Function baseline VM template
        # @param [Hash] conf_capacity Engine configuration attribute for max capacity assumptions
        #
        # @return [String] vm_template contents for a oneflow service template
        #
        def self.map_vm_template(specification, vm_template, conf_capacity)
            disk_size = specification['DISK_SIZE']
            disk_size ||= conf_capacity[:disk][:default]

            disk = vm_template.template_like_str("#{T}DISK")
            if disk.include?('SIZE=')
                disk.sub!("SIZE=\d+", "SIZE=\"#{disk_size}\"")
            else
                disk << "\n#{"SIZE=\"#{disk_size}\""}"
            end
            disk.gsub!(/"$/, '",').reverse!.sub!(',', '').reverse!

            cpu = specification['CPU']
            if !cpu
                cpu = vm_template["#{T}VCPU"].to_i
                cpu = conf_capacity[:cpu][:default] if cpu.zero?
            end

            memory = specification['MEMORY']
            if !memory
                memory = vm_template["#{T}MEMORY"].to_i
                memory = conf_capacity[:memory][:default] if memory.zero?
            end

            memory_max = memory * conf_capacity[:memory][:mult]
            vcpu_max = cpu * conf_capacity[:cpu][:mult]

            xaas = []

            xaas << "HOT_RESIZE=[CPU_HOT_ADD_ENABLED=YES,\nMEMORY_HOT_ADD_ENABLED=YES]"
            xaas << "MEMORY_RESIZE_MODE=#{conf_capacity[:memory][:resize_mode]}"
            xaas << "DISK=[#{disk}]"
            xaas << "CPU=#{cpu}"
            xaas << "VCPU=#{cpu}" # CPU = VCPU 1:1 ratio
            xaas << "MEMORY=#{memory}"
            xaas << "VCPU_MAX=#{vcpu_max}"
            xaas << "MEMORY_MAX=#{memory_max}"

            xaas.join("\n")
        end

        #
        # Translates specification parameters to Function VM USER_TEMPLATE
        #
        # @param [Hash] specification Serverless Runtime definition
        #
        # @return [String] User Template string compatible with opennebula VM Template
        #
        def self.map_user_template(specification)
            user_template = ''

            if specification.key?('SCHEDULING')
                specification['SCHEDULING'].each do |property, value|
                    user_template << "#{Function::SCHED_MAP[property]}=\"#{value.upcase}\"\n" if value
                end
            end

            if specification.key?('DEVICE_INFO')
                i_template = ''

                specification['DEVICE_INFO'].each do |property, value|
                    i_template << "#{property}=\"#{value}\",\n" if value
                end

                if !i_template.empty?
                    i_template.reverse!.sub!("\n", '').reverse!
                    i_template.reverse!.sub!(',', '').reverse!
                end

                user_template << "DEVICE_INFO=[#{i_template}]\n"
            end

            user_template
        end

        #
        # Creates a runtime function hash for the Serverless Runtime document
        #
        # @return [Hash] Function hash
        #
        def to_function
            function = {}

            function['VM_ID'] = @pe_id
            function['STATE'] = state_function

            if function['STATE'] == 'ERROR'
                if error
                    function['ERROR'] = error
                else
                    function['ERROR'] = 'No VM Error from Cloud Edge Manager'
                end
            end

            function['CPU'] = cpu[:vcpu]
            function['MEMORY'] = memory[:memory]
            function['DISK_SIZE'] = size
            function['ENDPOINT'] = endpoint

            function
        end

        #
        # CPU and Memory capacity resize operations for the Serverless Runtime Function
        #
        # @param [Hash] specification Desired VM state with capactiy changes
        #
        # @return [Array] [Response Code, ''/Error]
        #
        def resize_capacity?(specification, logger)
            capacity_template = []

            if specification['MEMORY'] != memory[:memory]
                capacity_template << "MEMORY=#{specification['MEMORY']}"
            end

            if specification['CPU'] != cpu[:vcpu]
                capacity_template << "VCPU=#{specification['CPU']}"
            end

            if specification['CPU'] != cpu[:cpu]
                capacity_template << "CPU=#{specification['CPU']}"
            end

            return [200, ''] if capacity_template.empty?

            capacity_template = capacity_template.join("\n")

            logger.info("Updating #{SRF} #{@id} capacity")
            logger.debug(capacity_template)

            response = resize(capacity_template, true)

            if OpenNebula.is_error?(response)
                rc = ProvisionEngine::Error.map_error_oned(response.errno)
                error = "Failed to resize #{SRF} capacity"
                return ProvisionEngine::Error.new(rc, error, response.message)
            end

            [200, '']
        end

        #
        # Disk resize operations for the Serverless Runtime Function as a Service Virtual Machine
        #
        # @param [Hash] specification Desired VM state with size changes
        #
        # @return [Array] [Response Code, ''/Error]
        #
        def resize_disk?(specification, logger)
            return [200, ''] unless specification['DISK_SIZE'] != size

            logger.info("Resizing #{SRF} #{@id} disk")
            logger.debug("From: #{size} To: #{specification['DISK_SIZE']}")

            response = disk_resize(0, specification['DISK_SIZE'])

            if OpenNebula.is_error?(response)
                rc = ProvisionEngine::Error.map_error_oned(response.errno)
                error = "Failed to resize #{SRF} disk"
                return ProvisionEngine::Error.new(rc, error, response.message)
            end

            [200, '']
        end

        def pending?
            state_function == STATES[:pending]
        end

        def running?
            state_function == STATES[:running]
        end

        def error?
            state_function == STATES[:error]
        end

        def updating?
            state_function == STATES[:updating]
        end

        #
        # Maps an OpenNebula VM state to the accepted Function VM states.
        # When the Function VM instance contains CONTEXT/REPORT_READY=YES
        # The RUNNING state for the Function will need to meet both hypervisor RUNNING
        # and onegate READY verification.
        #
        # @return [String] Serverless Runtime Function state
        #
        def state_function
            STATE_MAP.each do |function_state, lcm_states|
                if lcm_state_str == 'RUNNING'
                    return STATES[:running] unless report_ready?

                    return STATES[:running] if ready?

                    return STATES[:pending]
                end

                return function_state if lcm_states.include?(lcm_state_str)
            end

            return STATES[:updating]
        end

    end

end
