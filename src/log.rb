require 'logger'

module ProvisionEngine

    class Logger

        LOG_FILE = 'logfile.log'

        def initialize
            @logger = Logger.new(LOG_FILE)
            @logger.formatter = proc {|severity, datetime, _, msg|
                "[#{datetime}] #{severity.upcase}: #{msg}\n"
            }
        end

        def debug(message)
            @logger.debug(message)
        end

        def info(message)
            @logger.info(message)
        end

        def warning(message)
            @logger.warn(message)
        end

        def error(message)
            @logger.error(message)
        end

    end

end
