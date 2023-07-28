require_relative '../log'

# Example usage:
logger = ProvisionEngine::Logger.new

# Received REST API Calls
logger.info('Received REST API Call: /api/some_endpoint')

# Successful execution of API call
response_code = 200
if response_code == 200
    logger.info('API call executed successfully: /api/some_endpoint')
else
    logger.error("API call failed. Response code: #{response_code}. Cause: Invalid input data.")
end

# Service Initialization
logger.info('Service initialized successfully')

# Loading configuration files
logger.debug('Loading configuration file: config.yml')
