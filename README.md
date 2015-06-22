# rsa_sa_backup

RSA Securiy Analytics Backup tool

Author : Maxim Siyazov 

sa_backup is a tool to take a backup of configurations of all Security Analytics components available on the appliance 
Tested with versions 10.3, 10.4.   

Because in 10.4 some configurations are managed by puppet the sa_backup does not save those files, such as rabbitmq, collectd, tokumx, mcollective and puppet provisioned ssl files.

So far the tool does NOT do:
- Remote backup - on its way.
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
  - MongoDB (entire dump of the mongodb instance of SA or ESA servers)
  - PostgreSQL database (10.3)
  - Malware Analysis 
  - ESA server 
  - System Management Service (SMS)
  - Incident Management (IM) 
  - Log Collector (configuration and statDB)
  - Warehouse Connector

* After taking a backup the tool restores the original service status (start/stop)
* Logs the progress to a file
* Logs fatal errors to syslog
* Checks if the tool is already running
* Removes archives older than "n" days. 
* Rotates log file

### Usage

Edit the initialization section before running the script
```
BACKUPPATH=/root/sabackups				# The backup directory
LOG=sa_backup.log						# the backup log file
LOG_MAX_DIM=10000000 					# Max size of log file in bytes - 10MB 
RETENTION_DAYS=1						# Local backups retention 
RE_FULLBACKUP=0							# 0 - backup only RE configuration; 1 - full RE backup 
```
This script must be run as "root" user. 

### Contributing

1. Fork it!
2. Create your feature branch: `git checkout -b my-new-feature`
3. Commit your changes: `git commit -am 'Add some feature'`
4. Push to the branch: `git push origin my-new-feature`
5. Submit a pull request :D

### Version history

1.0.6   
        * Optimized the core services backup. Saving files without stopping services 
        * Consolidated into a single file SA server backup: uax, jetty and carlos keystores
        * Fixed RSA SMS backup -  added db directory. 
        * Changes around puppetmaster backup. Fuller backup.          
        * Disabled a single tar creation as redundant 

1.0.5	
        * Bug fixes: mcollective backup; single tar creation and cleanup.

1.0.4
        + Added RSA SMS backup
        * Fixed pupetmaster backup (added entire /etc/puppet)
        + tarball all archives in a single file
        + Added mcollective backup
        * Now taking ifcfg-*[0-9] instead of ifcfg-eth*
        + Disabling HWADDR parameter in network configuration scripts before archiving 
        * Added support for 10.5

1.0.3
        * Fixed SA version check

1.0.2		
		* Fixed removing old archives
		+ SA version check (based on Joshua Newton code)
		+ Improved user/log output. Added list of components to be backed up
		+ Improved RabbitMQ configuration backup
		+ Added support of 10.3
		+ Added PestgreSQL backup for 10.3

1.0.1		
		+ Code refactoring around service start/stop
		* Bug fixes

1.0.0	- Initial version
			
### License

  This script is free software: you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free Software
  Foundation, either version 2 of the License, or (at your option) any later
  version.
  
  This script is distributed in the hope that it will be useful, but WITHOUT
  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
  FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
  Please refer to the GNU General Public License <http://www.gnu.org/licenses/>

