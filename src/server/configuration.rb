module ProvisionEngine

    #
    # Abstraction to deserialize engine.conf config file
    #
    class Configuration < Hash

        PATH = '/etc/provision-engine/engine.conf'
        SCHEMA = JSON.load_file('/etc/provision-engine/schemas/config.json').freeze

        DEFAULTS = {
            :one_xmlrpc => 'http://localhost:2633/RPC2',
            :oneflow_server => 'http://localhost:2474',
            :host => '127.0.0.1',
            :port => 1337,
            :timeout => 30,
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
                    :mult => 2,
                    :resize_mode => 'BALLOONING'
                }
            },
            :log => {
                :level => 2,
                :system => 'file'
            }
        }

        def initialize
            replace(DEFAULTS)

            begin
                merge!(YAML.load_file(PATH))
                JSON::Validator.validate!(SCHEMA, self)
            rescue StandardError => e
                raise "Failed to load configuration at #{PATH}\n#{e}"
            rescue JSON::Schema::ValidationError => e
                raise "Invalid configuration at #{PATH}\n#{e}"
            end

            super
        end

    end

end
