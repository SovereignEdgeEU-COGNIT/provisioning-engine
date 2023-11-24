RSpec.shared_context 'logs' do
    it 'print every log' do
        logcation = '/var/log/provision-engine'
        sep = '-'*32
        pp sep

        Dir.entries(logcation).each do |entry|
            next if ['.', '..'].include?(entry)

            pp entry
            pp sep
            pp File.read("#{logcation}/#{entry}")
            pp sep
        end
    end
end
