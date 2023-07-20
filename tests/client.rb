#!/usr/local/opt/ruby/bin/ruby

require_relative '../src/client'

def tests(client)
    test_vm_id = 9328
    vm = client.vm_get(test_vm_id)
    puts vm.id
end

credentials = ARGV[0]
client = ProvisionEngine::CloudClient.new(credentials)
tests(client)
