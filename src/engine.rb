#!/usr/local/opt/ruby/bin/ruby

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

# Shared Libraries for Modules
require 'json'
require 'yaml'

parent_directory = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(parent_directory)

# Engine Modules
require 'log'
require 'configuration'

require 'runtime'
require 'data'
require 'function'

require 'client'

require 'api'

module ProvisionEngine

    #
    # Orchestrator. Initializes components and connects them.
    #
    class Engine

        def initialize
            @conf	= Configuration.new

            @logger = Logger.new(@conf)
            @client = CloudClient.new(@conf, @logger)
            @api = API.new(@conf, @client)
        end

        def stop
            @logger.info('Stopping Provision Engine')
            @api.kill
        end

    end

end
