module ProvisionEngine

    #
    # Error representation give to the Provision Engine Client in case of request error
    # Additional helpers to verify OpenNebula errors by code and message
    #
    # TODO: schema
    class Error < Array

        def initialize(code, error, message = '')
            super()

            self[0] = code
            self[1] = {
                'error' => error,
                'message' => message
            }
        end

        def self.wrong_document_type?(code, message)
            regex = /\[DocumentInfo\] Error getting document \[\d+\]\./

            code == 500 && message.match?(regex)
        end

        def self.service_deploying?(code, message)
            code == 500 && message == 'Service cannot be undeployed in state: DEPLOYING'
        end

        def self.map_error_oned(xmlrpc_errno)
            # ESUCCESS        = 0x0000
            # EAUTHENTICATION = 0x0100
            # EAUTHORIZATION  = 0x0200
            # ENO_EXISTS      = 0x0400
            # EACTION         = 0x0800
            # EXML_RPC_API    = 0x1000
            # EINTERNAL       = 0x2000
            # EALLOCATE       = 0x4000
            # ENOTDEFINED     = 0xF001
            # EXML_RPC_CALL   = 0xF002

            case xmlrpc_errno
            when OpenNebula::Error::EAUTHORIZATION
                403
            when OpenNebula::Error::ENO_EXISTS
                404
            else
                500
            end
        end

    end

end
