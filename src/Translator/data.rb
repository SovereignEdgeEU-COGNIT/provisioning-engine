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
