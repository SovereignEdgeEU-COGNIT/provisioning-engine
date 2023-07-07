require 'yaml'

module ProvisionEngine

    class Configuration < Hash

        DEFAULTS = {
            :one_xmlrpc => 'http://localhost:2633/RPC2',
            :oneflow_server => 'http://localhost:2474',
            :host => '127.0.0.1',
            :port => 2719,
            :log => {
                :level => 2,
                :system => 'file'
            }
        }

        FIXED = {
            :document_type => 1337,
            :configuration_path => '/etc/one/provision_engine.conf'
        }

        def initialize
            replace(DEFAULTS)

            begin
                merge!(YAML.load_file(FIXED[:configuration_path]))
            rescue StandardError => e
                STDERR.puts e
            end

            super
        end

    end

end
