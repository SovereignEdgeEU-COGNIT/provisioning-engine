# Provisioning Engine

Provisioning Engine acts as a entry point for the Device Runtime, instructs the Cloud-Edge Manager to spawn new FaaS/DaaS Runtimes and returns the endpoint back to the device. Afterwards, manages the lifetime of the FaaS/DaaS Runtimes

## Installation

Executte `./install.sh`. The installer will take care of

- installing the required dependencies
- distributing the default configuration
- distributing the engine libraries and executables

Files are installed by symlinking from this github repository to the installation directories.

### Permissions

Write permissions are required on the following directories

- `/etc`
- `/opt`
- `/usr/local/bin`
- `/var/log/`

The installer needs to write in those to distribute configuration. The engine will start logging onto `/var/log` once it starts.

### Dependencies

The following ruby gems are required

- sinatra
- logger
- opennebula

The installer will fetch these.

## Use

Execute `provision-engine start` and `provision-engine stop` to start the engine stop it respectively.

```log
root@ubuntu2004-9577:~# provision-engine-server start
/var/lib/gems/2.7.0/gems/sinatra-3.0.6/lib/sinatra/base.rb:931: warning: constant Tilt::Cache is deprecated
[2023-07-27 23:18:59] INFO  WEBrick 1.6.0
[2023-07-27 23:18:59] INFO  ruby 2.7.0 (2019-12-25) [x86_64-linux-gnu]
== Sinatra (v3.0.6) has taken the stage on 1337 for development with backup from WEBrick
[2023-07-27 23:18:59] INFO  WEBrick::HTTPServer#start: pid=2475 port=1337
```

The logs can be found at `/var/log/provision-engine/engine.log`

```log
root@ubuntu2004-9577:~# cat /var/log/provision-engine/engine.log
# Logfile created on 2023-07-27 23:20:28 +0000 by logger.rb/v1.5.3
I, [2023-07-27 23:20:28 #2516]  INFO -- : Initializing Provision Engine component: engine
I, [2023-07-27 23:20:28 #2516]  INFO -- : Using oned at http://localhost:2633/RPC2
I, [2023-07-27 23:20:28 #2516]  INFO -- : Using oneflow at http://localhost:2474
```

## Uninstall

Execute `./install.sh clean`. It will only remove the distributed files. Dependencies and created directories will remain.

## Development

Refer to [Specification Document](https://docs.google.com/document/d/1O_XLzS6TNsQoGvi5883g6Qi9s3EirahB1ADJEg34K0c/edit)

### Data Model

Provisioning Engine is stateless, all the state is saved in the Document Pool of OpenNebula.
