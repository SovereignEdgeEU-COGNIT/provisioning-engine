module ProvisionEngine

    #
    # Logging system for the provision engine components
    #
    class Logger

        # Directory that holds component logs
        LOGS = '/var/log/provision-engine'
        # Mapping of log levels to their corresponding methods in each logging system
        LOG_LEVEL_METHODS = {
            'file' => {
                :error => :error, :warning => :warn, :info => :info, :debug => :debug
            },
            'syslog' => {
                :error => :err, :warning => :warning, :info => :info, :debug => :debug
            }
        }

        #
        # @param [Hash] config Log configuration as defined in provision_engine.conf
        # @param [String] component File where the logs will be written
        #
        def initialize(config, component = 'engine')
            @component = component

            @system = config[:system] || 'file'

            case @system
            when 'file'
                initialize_file_logger(config[:level])
            when 'syslog'
                initialize_syslog_logger
            else
                msg = "Invalid logging system: #{@system}. Fallback to file logging"
                STDERR.puts msg

                initialize_file_logger(config[:level])
            end

            define_log_level_methods
            info("Initializing Provision Engine component: #{component}")
        end

        private

        def initialize_file_logger(level)
            FileUtils.mkdir_p(LOGS) unless Dir.exist?(LOGS)
            file = File.join(LOGS, "#{@component}.log")

            # TODO: Enable optional rotation on logger.new for CloudClient debugging
            # log rotation
            FileUtils.mv(file, "#{file}.#{Time.now.to_i}") if File.exist?(file)

            @logger = ::Logger.new(file)
            @logger.level = level || ::Logger::INFO
            @logger.datetime_format = '%Y-%m-%d %H:%M:%S'
        end

        def initialize_syslog_logger
            Syslog.open(@component, Syslog::LOG_PID, Syslog::LOG_USER)
        end

        #
        # Dynamically define methods for each supported logging level based on the log system
        #
        def define_log_level_methods
            LOG_LEVEL_METHODS[@system].each do |level, method_name|
                define_singleton_method(level) do |message|
                    if @system == 'file'
                        @logger.send(method_name, message)
                    elsif @system == 'syslog'
                        Syslog.send(method_name, message)
                    end
                end
            end
        end

    end

end
