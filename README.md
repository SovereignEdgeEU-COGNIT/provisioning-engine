# Provisioning Engine

Provisioning Engine acts as a entry point for the Device Runtime, instructs the Cloud-Edge Manager to spawn new FaaS/DaaS Runtimes and returns the endpoint back to the device. Afterwards, manages the lifetime of the FaaS/DaaS Runtimes

## Installation

Execute `./install.sh`. The installer will take care of

- installing the required dependencies
- distributing the default configuration
- distributing the engine libraries and executables

By default, files are installed by symlinking from the github repository directory to the installation directories. You can use `./install.sh copy` to issue a file copy instead.

### Permissions

Write permissions are required on the following directories as a regular user

- `/opt`
- `/var/log/`

These require sudo

- `/etc`
- `/usr/local/bin`

### Dependencies

The following ruby gems are required. They will be installed automatically by `./install.sh`.

- sinatra
- logger
- json-schema
- opennebula

### Pre requirements

Each serverless runtime is associated to a running oneflow service. This service is the result of a service template instantiation. This template is a map from the functions defined in the runtime specification. It can be configured at `/etc/provision-engine/engine.conf`

```yaml
# nature -> A flow template with a FasS role called nature
# nature-s3 -> A flow template with a FasS role called nature and a DaaS role called s3
:mapping:
  :nature: 0
  :nature-s3: 3
```

## Service control

Execute `provision-engine start` and `provision-engine stop` to start the engine stop it respectively.

```log
 ~  provision-engine-server start
[2023-08-28 18:10:29] INFO  WEBrick 1.8.1
[2023-08-28 18:10:29] INFO  ruby 3.2.2 (2023-03-30) [x86_64-darwin22]
== Sinatra (v3.0.6) has taken the stage on 1337 for development with backup from WEBrick
[2023-08-28 18:10:29] INFO  WEBrick::HTTPServer#start: pid=99612 port=1337
127.0.0.1 - - [28/Aug/2023:18:12:12 -0600] "POST /serverless-runtimes HTTP/1.1" 201 821 2.3746
127.0.0.1 - - [28/Aug/2023:18:12:10 CST] "POST /serverless-runtimes HTTP/1.1" 201 821
- -> /serverless-runtimes
```

### Logs

The log files for the different engine components can be found at `/var/log/provision-engine/`. You can customize the log level at `/etc/provision-engine/engine.conf`

```yaml
# Log debug level
#   3 = ERROR, 2 = WARNING, 1 = INFO, 0 = DEBUG
#
# System
#   - file: log to log file
#   - syslog: log to syslog
:log:
  :level: 0
  :system: 'file'
```

Engine specific logs are written to the file `engine.log`. These contain information related to the API Calls

```log
# Logfile created on 2023-08-28 18:31:34 -0600 by logger.rb/v1.5.3
I, [2023-08-28 18:31:34 #2724]  INFO -- : Initializing Provision Engine component: engine
I, [2023-08-28 18:31:34 #2724]  INFO -- : Using oned at http://localhost:1338/RPC2
I, [2023-08-28 18:31:34 #2724]  INFO -- : Using oneflow at http://localhost:1339
I, [2023-08-28 18:31:50 #2724]  INFO -- : Received request to Create a Serverless Runtime
I, [2023-08-28 18:31:52 #2724]  INFO -- : Response HTTP Return Code: 201
D, [2023-08-28 18:31:52 #2724] DEBUG -- : Response Body: #<ProvisionEngine::ServerlessRuntime:0x00000001111d2df8>
I, [2023-08-28 18:31:52 #2724]  INFO -- : Serverless Runtime created
```

Each time a call is issued, the engine uses a component called the CloudClient which takes care of interacting with OpenNebula. These interactions are logged to `CloudClient.log`

```log
# Logfile created on 2023-08-28 18:31:50 -0600 by logger.rb/v1.5.3
I, [2023-08-28 18:31:50 #2724]  INFO -- : Initializing Provision Engine component: CloudClient
I, [2023-08-28 18:31:50 #2724]  INFO -- : Creating oneflow Service for Serverless Runtime
D, [2023-08-28 18:31:50 #2724] DEBUG -- : Instantiating service_template 0 with options {"name"=>"nature5c2e4955-3a33-4772-a46a-bf28761a2619"}
I, [2023-08-28 18:31:50 #2724]  INFO -- : Serverless Runtime Service created
D, [2023-08-28 18:31:51 #2724] DEBUG -- : {"DOCUMENT"=>{"ID"=>"77", "UID"=>"0", "GID"=>"0", "UNAME"=>"oneadmin", "GNAME"=>"oneadmin", "NAME"=>"nature5c2e4955-3a33-4772-a46a-bf28761a2619", "TYPE"=>"100", "PERMISSIONS"=>{"OWNER_U"=>"1", "OWNER_M"=>"1", "OWNER_A"=>"0", "GROUP_U"=>"0", "GROUP_M"=>"0", "GROUP_A"=>"0", "OTHER_U"=>"0", "OTHER_M"=>"0", "OTHER_A"=>"0"}, "TEMPLATE"=>{"BODY"=>{"name"=>"nature5c2e4955-3a33-4772-a46a-bf28761a2619", "deployment"=>"straight", "description"=>"", "roles"=>[{"name"=>"FaaS", "cardinality"=>1, "vm_template"=>0, "elasticity_policies"=>[], "scheduled_policies"=>[], "vm_template_contents"=>"", "state"=>1, "cooldown"=>300, "nodes"=>[{"deploy_id"=>114, "vm_info"=>{"VM"=>{"ID"=>"114", "UID"=>"0", "GID"=>"0", "UNAME"=>"oneadmin", "GNAME"=>"oneadmin", "NAME"=>"FaaS_0_(service_77)"}}}], "on_hold"=>false, "last_vmname"=>1}], "ready_status_gate"=>false, "automatic_deletion"=>false, "registration_time"=>1692200149, "state"=>1, "start_time"=>1693269110, "log"=>[{"timestamp"=>1693269110, "severity"=>"I", "message"=>"New state: DEPLOYING_NETS"}, {"timestamp"=>1693269110, "severity"=>"I", "message"=>"New state: DEPLOYING"}]}}}}
I, [2023-08-28 18:31:51 #2724]  INFO -- : Allocating Serverless Runtime Document
D, [2023-08-28 18:31:51 #2724] DEBUG -- : {"FAAS"=>{"FLAVOUR"=>"nature", "ENDPOINT"=>"http://localhost:1339", "VM_ID"=>"114", "STATE"=>"PENDING", "CPU"=>"1", "MEMORY"=>"128", "DISK_SIZE"=>"256"}, "SCHEDULING"=>{}, "DEVICE_INFO"=>{}, "SERVICE_ID"=>"77"}
I, [2023-08-28 18:31:52 #2724]  INFO -- : Created Serverless Runtime Document
```

## Uninstall

Execute `./install.sh clean`. It will only remove the engine libraries. Gem dependencies and configuration will remain installed. Alternatively issue `./install.sh clean purge` to remove everything. The gems will be removed unless they are required by other gems already installed in the system.

## Development

Refer to [Specification Document](https://docs.google.com/document/d/1O_XLzS6TNsQoGvi5883g6Qi9s3EirahB1ADJEg34K0c/edit)

### Data Model

Provisioning Engine is stateless, all the state is saved in the Document Pool of OpenNebula.
