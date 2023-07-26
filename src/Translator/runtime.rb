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

    # Serverless runtime class as wrapper of DocumentJSON
    class ServerlessRuntime < OpenNebula::DocumentJSON

        DOCUMENT_TYPE = 1337

        def allocate(template)
            template = JSON.parse(template)
            FaaS.valid_definition?(template)

            template['registration_time'] = Integer(Time.now)

            super(template.to_json, template['name'])
        end

        # Ensures the submitted template is valid
        def self.valid_definition?(template)
            return false unless template

            true
        end

    end

end
