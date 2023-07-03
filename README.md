# provisioning-engine

Provisioning Engine acts as a entry point for the Device Runtime, instructs the Cloud-Edge Manager to spawn new FaaS/DaaS Runtimes and returns the endpoint back to the device. Afterwards, manages the lifetime of the FaaS/DaaS Runtimes

# Data Model

Provisioning Engine is stateless, all the state is saved in the Document Pool of OpenNebula
