# -------------------------------------------------------------------------- #
# Copyright 2023, OpenNebula Project, OpenNebula Systems                     #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #

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
