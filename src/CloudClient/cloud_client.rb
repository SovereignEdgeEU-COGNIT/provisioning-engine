############################################################################
# Environment Configuration
############################################################################
ONE_LOCATION = ENV['ONE_LOCATION']

if !ONE_LOCATION
    RUBY_LIB_LOCATION = '/usr/lib/one/ruby'
    GEMS_LOCATION     = '/usr/share/one/gems'
else
    RUBY_LIB_LOCATION = ONE_LOCATION + '/lib/ruby'
    GEMS_LOCATION     = ONE_LOCATION + '/share/gems'
end

if File.directory?(GEMS_LOCATION)
    real_gems_path = File.realpath(GEMS_LOCATION)
    if !defined?(Gem) || Gem.path != [real_gems_path]
        $LOAD_PATH.reject! {|l| l =~ /vendor_ruby/ }
        require 'rubygems'
        Gem.use_paths(real_gems_path)
    end
end

$LOAD_PATH << RUBY_LIB_LOCATION

############################################################################
# Required libraries
############################################################################
require 'opennebula'
include OpenNebula

require_relative 'configuration'

module ProvisionEngine

    #
    # A class to abstract the OpenNebula client that will be used to issue XMLRPC calls
    #
    class CloudClient

        attr_reader :conf

        def initialize
            @conf = ProvisionEngine::Configuration.new
            @credentials = self.class.load_credentials

            @one_client = OpenNebula::Client.new(@credentials, @conf[:one_xmlrpc])

            log_init if @conf[:log][:level] >= 2
        end

        #
        # Looks the user credentials on environmental variables.
        # Then proceeds to look for the one_auth file if no ENV
        #
        # @return [String] Credentials that should be formatted as user:password
        #
        def self.load_credentials
            credentials = nil

            auth = 'ONE_AUTH'
            path = "#{Dir.home}/.one/#{auth.downcase}"

            begin
                if ENV.key?(auth)
                    credentials = File.read(ENV[auth])
                elsif File.exist?(path)
                    credentials = File.read(path)
                end
            rescue StandardError => e
                err_msg = "Failed to load authentication for #{self}\n#{e}"

                STDERR.puts err_msg
                exit 1
            end

            if credentials.nil?
                err_msg =  "No valid authentication found for #{self}"
                err_msg << "Setup valid credentials on the environmental variable #{auth}"
                err_msg << "or in the filesystem at #{path}"

                STDERR.puts err_msg
                exit 1
            end

            credentials
        end

        def vms
            VirtualMachinePool.new(@one_client, -1)
        end

        # TODO: Use log file
        def log_init
            puts "Using oned at #{@conf[:one_xmlrpc]} as user #{@credentials.split(':')[0]}"
        end

    end

end
