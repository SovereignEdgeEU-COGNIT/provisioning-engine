#!/usr/local/opt/ruby/bin/ruby

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

require 'json'
require 'yaml'

parent_directory = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(parent_directory)

require 'log'
require 'configuration'
require 'faas'
require 'client'
require 'rest'

module ProvisionEngine

    class Engine

        def initialize
            @conf	= Configuration.new
            @logger = Logger.new(@conf)
            @client = CloudClient.new(@conf)

			# start rest API
        end

    end

end
