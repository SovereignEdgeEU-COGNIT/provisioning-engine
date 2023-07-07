#!/usr/local/opt/ruby/bin/ruby

require 'opennebula'

require_relative 'cloud_client'

def tests(client)
    vms = client.vms

    vms.each do |vm|
        puts vm.name
    end
end

client = ProvisionEngine::CloudClient.new
tests(client)
