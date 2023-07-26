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

module ProvisionEngine

    # "DAAS": {
    #   "type": "object",
    #   "properties": {
    #     "CPU": {
    #       "type": "integer"
    #     },
    #     "MEMORY": {
    #       "type": "integer"
    #     },
    #     "DISK_SIZE": {
    #       "type": "integer"
    #     },
    #     "FLAVOUR": {
    #       "type": "string"
    #     },
    #     “ENDPOINT”: {
    #       “type”:  “string”
    #     },
    #     “STATE”: {
    #       “type”: “string”
    #     },
    #     “VM_ID”: {
    #       “type”: “string”
    #     }
    #   }
    # },

	# TODO: Maybe DaaS and FaaS should be the same class with different type
    class DaaS < OpenNebula::VirtualMachine

        def initialize(definition); end

    end

end
