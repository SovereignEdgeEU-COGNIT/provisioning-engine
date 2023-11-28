module ProvisionEngine

    #
    # Abstraction to deserialize engine.conf config file
    #
    class Configuration < Hash

        DEFAULTS = {
            :one_xmlrpc => 'http://localhost:2633/RPC2',
            :oneflow_server => 'http://localhost:2474',
            :host => '127.0.0.1',
            :port => 1337,
            :capacity => {
                :disk => {
                    :default => 1024
                },
                :cpu => {
                    :default => 2,
                    :mult => 2
                },
                :memory => {
                    :default => 1024,
                    :mult => 2
                }
            },
            :log => {
                :level => 2,
                :system => 'file'
            }
        }

        PATH = '/etc/provision-engine/engine.conf'

        # TODO: Validate config values type on load
        def initialize
            replace(DEFAULTS)

            begin
                merge!(YAML.load_file(PATH))
            rescue StandardError => e
                STDERR.puts e
            end

            super
        end

    end

end
