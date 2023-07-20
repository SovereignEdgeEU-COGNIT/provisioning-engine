require_relative '/opt/ProvisionEngine'

engine = ProvisionEngine::Engine.new

ttl = 300
sleep ttl

engine.stop
