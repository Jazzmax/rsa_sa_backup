# rsa_sa_backup

RSA Securiy Analytics Configuration Backup tool

Author : Maxim Siyazov 

sa_backup is a tool to take a backup of configurations  and some opertional data of all Security Analytics components of the appliance.
Tested with versions 10.3, 10.4, 10.5, 10.6. 

The SA_BACKUP tool is a bash 4 script and depends on packages that are part of the standard SA appliance image. No extra package is required. 

Because in 10.4 and higher most of configuration files such as rabbitmq, collectd, tokumx, and mcollective are managed by puppet, so sa_backup does not save those files. 

The tool does NOT do:
- Backup of packets, meta, sessions or index data. 
- Backup of a license server (fneserver).


### Features

* The following components are backed up:
  - OS configuration files:
    - /etc/sysconfig/network-scripts/ifcfg-*[0-9] - HWADDR is disabled
    - /etc/sysconfig/network
    - /etc/hosts
    - /etc/resolv.conf
    - /etc/ntp.conf
    - /etc/fstab - renamed to fstab.{hostname} to prevent overwriting the original fstab on restore
    - /etc/krb5.conf
  - Puppet configuration (puppetmaster, puppet client, ssl files, node_id, puppet.conf, csr_attributes.yaml, mcollective configuration)
  - Core Appliance Services configuration (/etc/netwitness/ng)
  - SA server configuration (/var/lib/netwitness/uax, jetty keystore, jetty-ssl.xml)
  - Reporting Engine (configuration or full backup (optional))
  - RabbitMQ server (mnesia database, configuration for 10.3)
  - MongoDB (entire dump of the mongodb instance of SA and ESA servers)
  - PostgreSQL database (10.3)
  - Malware Analysis configuration
  - ESA server configuration
  - System Management Service (SMS) configuration
  - Incident Management (IM) configuration and DB (incidents, alerts, remediation tasks).
  - Log Collector (configuration and statDB)
  - Warehouse Connector 
  - Custom user files

* After taking a backup the tool restores the original service status (start/stop)
* Logs the progress to a file
* Logs fatal errors to syslog
* Checks if the tool is already running
* Removes archives older than "n" days. 
* Rotates log file
* Command line arguments - see the usage information.
* Inline or file configuration to enable/disable backup of components
* Option to backup custom user files
* Test mode
* Remote backup to NFS


TO DO:
- SCP remote backup.


### Usage
```
Usage: ./sa_backup.sh [OPTION...]

Please modify the configuration section in the script or use an external configuration file.

Examples:
  sa_backup --config=backup.conf --verbose

  sa_backup --backuponly=CORE

Main operation mode:

-c, --config=CONFIG_FILE      Use configuration file
-b, --backuponly=COMPONENTS   Backup only specified components:
                                  CORE - Core services
                                  SYS - OS configuration
                                  PUPPET - puppet master/agent configuration
                                  RABBITMQ - rabbitmq configuration
                                  MONGO - MongoDB/tokumx dump
                                  JETTY - SA application server settings
                                  RE - Reporting Engine
                                  MALWARE - Malware Analysis configuration
                                  ESA - Event Stream Analysis configuration
                                  IM - Incidint Management configuration
                                  IMDB - Incidint Management DB
                                  SMS - System Management System
                                  LC - Log collector
                                  WHC - Warehouse connector
                                  PGQSL - PostgreSQL database
-t, --test                    Test mode; no backup performed
-v, --verbose                 tar verbose switch
-?, -h, --help                Give this help list
```

The script being executed without arguments will try to identify all available on the appliance components and according to the current inline configuration will take a backup. 
Please note it will stop some of the SA services, which will lead to a short downtime. Use --test option to see the current configuration.


Edit the configuration section in the script before running it.
```
BACKUP_TYPE=local                       # local | nfs 
BACKUPPATH=/root/sabackups              # Local backup directory
LOG=sa_backup.log                       # The backup log file
LOG_MAX_DIM=10000000                    # Max size of log file in bytes - 10MB 
RETENTION_DAYS=0                        # Local backups retention in days (0 - no cleanup)
          
# System files 
SYS_ENABLED=true

# SA server / Jetty server
SASERVER_ENABLED=true

# Reporting engine
RE_ENABLED=true
RE_FULLBACKUP=1                         # 0 - backup only RE configuration; 
                                        # 1 - full RE backup
# Puppet 
PUPPET_ENABLED=true
. . .
```

This script must be run as "root" user. 

**For more information see the [Wiki](https://github.com/Jazzmax/rsa_sa_backup/wiki/SA-Backup-Tool)**


### Contributing

1. Fork it!
2. Create your feature branch: `git checkout -b my-new-feature`
3. Commit your changes: `git commit -am 'Add some feature'`
4. Push to the branch: `git push origin my-new-feature`
5. Submit a pull request :D


### License

  This script is free software: you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free Software
  Foundation, either version 2 of the License, or (at your option) any later
  version.
  
  This script is distributed in the hope that it will be useful, but WITHOUT
  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
  FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
  Please refer to the GNU General Public License <http://www.gnu.org/licenses/>

