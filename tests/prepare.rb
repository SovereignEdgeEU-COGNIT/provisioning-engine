#!/usr/bin/env ruby
require 'yaml'
require 'tempfile'

# How to use
# ./prepare.rb http://one_host:2633/RPC2 http://one_host:2474 0 1

GEMS = ['rspec', 'rack-test'] # gems required for running the tests
CONF_PATH = '/etc/provision-engine/engine.conf'

def install_gems
    GEMS.each do |gem|
        system("sudo gem list -i #{gem} || sudo gem install #{gem}")
    end
end

def configure_engine(oned, oneflow)
    config = YAML.load_file(CONF_PATH)

    config[:one_xmlrpc] = oned if oned
    config[:oneflow_server] = oneflow if oneflow
    config[:log][:level] = 0

    tempfile = Tempfile.new('engine.conf')
    tempfile.write(config)
    tempfile.flush

    File.open(tempfile, 'w') do |f|
        f.write(config.to_yaml)
    end

    system("sudo mv #{tempfile.path} #{CONF_PATH}")
end

endpoint_oned = ARGV[0]
endpoint_oneflow = ARGV[1]

install_gems
configure_engine(endpoint_oned, endpoint_oneflow)
