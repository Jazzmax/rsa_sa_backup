# Change Log
All notable changes to this project will be documented in this file.

### Unreleased
**Added**
- Disk space check
- Version information file 

### 1.0.11 - 2016-02-14
**Added**
* Added a remote backup to NFS
+ Added components backup ordering. Thanks to Lee McCotter
**Changed**
+ Remote backup to NFS 
- Removed MCollective backup as redundant (fully puppet managed service)
* Excluded feeds from Core appliance backup
* Bug fixes and stability improvements          

### 1.0.10 - 2015-11-25
**Changed**
* Excluded log files from ESA, SMS, IM backup 
* Improved Puppet backup. Stopping the puppet master only on SA server.  

### 1.0.9 -  2015-09-14
**Fixed** 
* Fixed: Mongo backup never taken
  
### 1.0.8 - 2015-09-08
**Fixed**
* Fixed a typo in the ESA backup configuration

### 1.0.7 - 2015-09-07
**Added**
+ Added command line arguments
+ Added an inline/file configuration to enable/disable backup of components
+ Added a new option to backup custom user files
+ Added a test mode
+ Added a tar progress indication
+ Added option to backup only one component - see the usage
**Changed**
* Exclude core files from the Warehouse connector backup
* Improved reporting engine exclusion list
**Fixed**
* Cleanup removing non-backup files and folders
        
### 1.0.6 - 2015-06-22
**Changed**  
* Optimized the core services backup. Saving files without stopping services 
* SA server backup consolidated into a single file including: uax, jetty and carlos keystores
* Changes around puppetmaster backup. Fuller backup.
* Disabled a single tar creation as redundant
**Fixed**
* Fixed RSA SMS backup - added the db directory. 

### 1.0.5 - 2015-06-19
**Changed**
* Mcollective backup;
* Single tar creation and cleanup

### 1.0.4 - 2015-06-19
**Added**
* Added support for SA 10.5
+ Added RSA SMS backup
+ Added mcollective backup
+ tarball all archives in a single file
**Changed**
+ Disabling HWADDR parameter in network configuration scripts before archiving
**Fixed**
* Fixed pupetmaster backup (added entire /etc/puppet)
* Now taking ifcfg-*[0-9] instead of ifcfg-eth*

### 1.0.3 - 2015-06-02
**Fixed**
* Fixed SA version check

### 1.0.2 - 2015-06-22
**Fixed**
* Fixed removing old archives
**Added**
+ SA version check (based on Joshua Newton code)
+ Improved user/log output. Added list of components to be backed up
+ Improved RabbitMQ configuration backup
+ Added support of 10.3
+ Added PestgreSQL backup for 10.3

### 1.0.1 - 2015-05-30
**Changed**
+ Code refactoring around service start/stop
* Bug fixes

### 1.0.0	- Initial version - 2015-05-29