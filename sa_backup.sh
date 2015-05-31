#!/bin/bash
VER=1.0.1
################################################################
##
## BACKUP SCRIPT for RSA Security Analytics 10.4.x
##
## The script compresses configuration files of all available on the box 
## SA services into the backup area.
## Old backups are removed after "n" days.
##
## Copyright (C) 2015 Maxim Siyazov 
##
##  This script is free software: you can redistribute it and/or modify it under
##  the terms of the GNU General Public License as published by the Free Software
##  Foundation, either version 2 of the License, or (at your option) any later
##  version.
##  This script is distributed in the hope that it will be useful, but WITHOUT
##  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
##  FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
##  Please refer to the GNU General Public License <http://www.gnu.org/licenses/>
##
################################################################
# # Version History
# 1.0.0		- Initial version
# 1.0.1		+ Code refactoring around service start/stop
#			* Bug fixes
#---------------------------------------------------------------
# TO DO:
# - remote backup files 
# - check if enough disk space to create a backup
# - not de-reference a symlink in /ng but take backup of the actual files  
# - 

################################################################
# Initialize and Tools Section
#

BACKUPPATH=/root/sabackups				# The backup directory
LOG=sa_backup.log						# the backup log file
LOG_MAX_DIM=10000000 					# Max size of log file in bytes - 10MB 
RETENTION_DAYS=1						# Local backups retention 
RE_FULLBACKUP=0							# 0 - backup only RE configuration; 1 - full RE backup 

# Remote backup
USER=backup
NAS=10.196.250.102
PATHNAS=/cygdrive/k/BACKUP_TSF_SA

HOST="$(hostname)"
timestamp=$(date +%Y.%m.%d.%H.%M) 
#SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_NAME="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
BACKUP="${BACKUPPATH}/${HOST}-$(date +%Y-%m-%d-%H-%M)"
SYSLOG_PRIORITY=local0.alert
TARSWITCHES="-cphzf"
PID_FILE=sa_backup.pid

# Colouring output
COL_BLUE="\x1b[34;01m"
COL_GREEN="\x1b[32;01m"
COL_RED="\x1b[31;01m"
COL_YELLOW="\x1b[33;01m"
COL_RESET="\x1b[39;49;00m"  

COREAPP=/etc/netwitness
DECCONBRK2=/var/log/netwitness
REPORTING=/home/rsasoc/rsa/soc/reporting-engine
SASERVER1=/var/lib/netwitness/uax
JETTYSRV=/opt/rsa/jetty9/etc
PUPPET1=/var/lib/puppet
PUPPET2=/etc/puppet
RSAMALWARE=/var/lib/netwitness/rsamalware
ESASERVER1=/opt/rsa/esa
IM=/opt/rsa/im
LOGCOL=/var/netwitness/logcollector
RABBITMQ=/var/lib/rabbitmq
NWSERVICES=() 
 
####################################################################
# Syslog a message
####################################################################
function syslogMessage()
{
	MESSAGE=$1
	logger -p $SYSLOG_PRIORITY "$HOST: $MESSAGE"
}
  
####################################################################
# Write to a log file
function writeLog()
{
    echo "$(date '+%Y-%m-%d %H:%M:%S %z') | $$ | $1" >> $LOG 
    echo "$(date '+%Y-%m-%d %H:%M:%S %z') | $$ | $1"	
}

#####################################################################
# If the supplied return value indicates an error, exit immediately
####################################################################
function exitOnError() {
	RETVAL=$1
	if [ $RETVAL != 0 ]; then
		syslogMessage "SA Appliance Backup Failed [$RETVAL] - Log File: $LOG"
        echo -e ${COL_RED}"$2"${COL_RESET}
		exit 1 # $RETVAL
	fi
}

#####################################################################
# If the supplied return value indicates an error, syslog a message but not exit
####################################################################
function syslogOnError() {
	RETVAL=$1
	if [ $RETVAL != 0 ]; then
		syslogMessage "$2"
        echo -e "${COL_RED}$2 - exit code: [$RETVAL] - Log File: $LOG${COL_RESET}"
	fi
}
####################################################################
# Check is run as root
####################################################################
check_root(){
  if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root!"
    echo ""
    exit 1
  fi
}

####################################################################
## Cleanup the Backup Staging Area
####################################################################
function do_Cleanup {
    find ${BACKUP} -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -Rf {} \; 2>&1 | tee -a $LOG;
    rm -f $PID_FILE
	
}
trap do_Cleanup HUP INT QUIT TERM EXIT
####################################################################
# Check if another instance is running
####################################################################
function check_isRun() {
    if [ -f $PID_FILE ]; then
       OLD_PID=$(cat $PID_FILE)
       DRES=$( ps auxwww | grep $OLD_PID | grep "$1" | grep -v grep | wc -l)
       if [[ "$DRES" = "1" ]]; then
          writeLog "ERROR: Exit because process sa_backup.sh is already running with pid $OLD_PID"
          exit 1
       else
          writeLog "INFO: Clean pid file because related to a dead process"
       fi
     fi
    echo $$ > $PID_FILE
}
####################################################################
# Rotate log file based on dimension
####################################################################
function rotate_Logs() {
	if [ -f $LOG ]; then
	   DIM=$(ls -la $LOG|awk '{print $5}')
	   if [ $DIM -gt $LOG_MAX_DIM ]; then
		  writeLog "INFO: Rotating log because of max size - $LOG is $DIM byte"
		  mv $LOG $LOG.old
	   fi
	fi
}
####################################################################
# Returns original service's status 
# ARGUMENTS:
# 1 - Service name
# 2 - Service type (upstart|init)
# 3 - Return variable (stop|start)
# Returns 1 - service started; 0 - stopped  
####################################################################
function check_ServiceStatus() {
	local _SERVICE=$1
	local _SERVICE_TYPE=$2
	local _RESULTVAR=$3
	local _RETURNVAL=0
	local __RESTART
	[[ "$_SERVICE_TYPE" = "init" ]] && _RETURNVAL=$(service ${_SERVICE} status | grep -E "is running|running_applications" | wc -l);
	[[ "$_SERVICE_TYPE" = "upstart" ]] && _RETURNVAL=$(status ${_SERVICE} | grep "start/running" | wc -l);
	if [ $_RETURNVAL -eq 1 ]; then 
		__RESTART="start"
	else 
		__RESTART="stop"
	fi
	eval $_RESULTVAR="'$__RESTART'"
	return $_RETURNVAL 
}

####################################################################
# Determine components present on the box
####################################################################
function what_to_backup() {
	recipe[0]="backup_etc"
	recipe[1]="backup_Puppet"
	
	if [ -d /var/lib/rabbitmq ]; then
		recipe+=("backup_RabbitMQ")
	fi
	if [ -d /etc/netwitness/ng ]; then
		recipe+=("backup_CoreAppliance")
	fi
	if [ -f /usr/bin/mongodump ]; then
		recipe+=("backup_Mongo")
	fi
	if [ -d /var/lib/netwitness/uax ]; then
		recipe+=("backup_Jetty")
	fi
	if [ -d /home/rsasoc/rsa/soc/reporting-engine ]; then
		recipe+=("backup_RE")
	fi
	if [ -d /var/lib/netwitness/rsamalware ]; then
		recipe+=("backup_Malware")
	fi
	if [ -d /opt/rsa/esa ]; then
		recipe+=("backup_ESA")
	fi
	if [ -d /opt/rsa/im ]; then
		recipe+=("backup_IM")
	fi	
	if [ -d /var/netwitness/logcollector ]; then
		recipe+=("backup_LC")
	fi
	if [ -d /var/netwitness/warehouseconnector ]; then
		recipe+=("backup_WHC")
	fi	
} 

####################################################################
## CORE APPLIANCE SERVICES: 
# Log Decoder, Archiver, Decoder, Concentrator, Broker, Log Collector, IPDBExtrator 
# COREAPP=/etc/netwitness/
####################################################################
function backup_CoreAppliance() {
	writeLog ""
	writeLog "Backup of ${COREAPP}"
	writeLog "Stopping SA Core services."
	NWSERVICES=('NwConcentrator' 'NwArchiver' 'NwDecoder' 'NwBroker' 'NwLogCollector' 'NwLogDecoder' 'NwIPDBExtractor')
	SERVICE_RESTART=()
	for i in "${NWSERVICES[@]}"
	do
		PROCESS="/usr/sbin/${i}"
		if [ -f "$PROCESS" ]; then
			if [ -n "`pidof "${i}"`" ]; then 
				SERVICENAME=`echo "${i}" | tr '[:upper:]' '[:lower:]'`
				SERVICE_RESTART+=("$SERVICENAME")
				stop "$SERVICENAME" 2>&1 | tee -a $LOG
			fi
		fi
	done

	writeLog "tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-etc-netwitness.$timestamp.tar.gz ${COREAPP}"
	tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-etc-netwitness.$timestamp.tar.gz ${COREAPP} --exclude=${COREAPP}/ng/Geo*.dat 2>&1 | tee -a $LOG
		syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive Core appliance configuration files ${COREAPP}."
		
	writeLog "Starting SA Core services"			
	for i in "${SERVICE_RESTART[@]}" 
	do
		start "${i}" 2>&1 | tee -a $LOG
	done
}	
####################################################################
# REPORTING ENGINE 
# REPORTING=/home/rsasoc/rsa/soc/reporting-engine
####################################################################
# Reporting Engine 
function backup_RE {
	writeLog "Backup of ${REPORTING}"
	EXCL_FILES=''
	local _RESTART
	#Backup only last 2 DB archives. Creating an exclude parameter for old DB archives files   
	for FILE in $(ls -1tr ${REPORTING}/archives | head -n -2)
	  do
		EXCL_FILES+=" --exclude=${REPORTING}/archives/${FILE}"
	  done

	check_ServiceStatus rsasoc_re upstart _RESTART || stop rsasoc_re 2>&1 | tee -a $LOG
	  
	if [ "$RE_FULLBACKUP" -eq 0 ]; then 
		writeLog "Backing up Reporting Engine configuration files..."
		writeLog "tar --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-home-rsasoc-rsa-soc-reporting-engine.$timestamp.tar.gz ${REPORTING}"
			tar --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-home-rsasoc-rsa-soc-reporting-engine.$timestamp.tar.gz ${REPORTING} \
			--exclude=${REPORTING}/formattedReports \
			--exclude=${REPORTING}/resultstore \
			--exclude=${REPORTING}/livecharts \
			--exclude=${REPORTING}/statusdb \
			--exclude=${REPORTING}/subreports \
			--exclude=${REPORTING}/temp \
			--exclude=${REPORTING}/logs \
			${EXCL_FILES} 2>&1 | tee -a $LOG
			syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive Reporting engine conf files ${REPORTING}."		
	else 
		writeLog "Full RE backup enabled."
		writeLog "tar --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-home-rsasoc-rsa-soc-reporting-engine.$timestamp.tar.gz ${REPORTING}"
		tar --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-home-rsasoc-rsa-soc-reporting-engine.$timestamp.tar.gz ${REPORTING} --exclude=${REPORTING}/temp 2>&1 | tee -a $LOG
			syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive Reporting engine files ${REPORTING}."	
		fi;
	
	$_RESTART rsasoc_re 2>&1 | tee -a $LOG
}

####################################################
## SA SERVER and JETTY 
# SASERVER1=/var/lib/netwitness/uax
# JETTYSRV=/opt/rsa/jetty9/etc	
####################################################
function backup_Jetty() {
	local _RESTART
	writeLog ""
	writeLog "Backup of ${SASERVER1}"
	check_ServiceStatus jettysrv upstart _RESTART || stop jettysrv 2>&1  && sleep 5 | tee -a $LOG
	EXCL_FILES=''
	#Backup only last 2 H2 DB archives. Creating an exclude parameter for old H2 DB archives files   
	for FILE in $(ls -1tr ${SASERVER1}/db/*.zip | head -n -2)
	  do
		EXCL_FILES+=" --exclude=${FILE}"
	  done 

	writeLog "tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-var-lib-netwitness-uax.$timestamp.tar.gz ${SASERVER1}"		 
	tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-var-lib-netwitness-uax.$timestamp.tar.gz ${SASERVER1} \
		--exclude=${SASERVER1}/temp \
		--exclude=${SASERVER1}/trustedStorage \
		--exclude=${SASERVER1}/cache \
		--exclude=${SASERVER1}/yum \
		--exclude=${SASERVER1}/logs/*_index \
		--exclude=${SASERVER1}/content \
		--exclude=${SASERVER1}/lib \
		${EXCL_FILES} 2>&1 | tee -a $LOG
		syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive SA server conf files ${SASERVER1}"	

	writeLog "Starting jetty server"		
	$_RESTART jettysrv 2>&1 | tee -a $LOG
	
	# Backup Jetty key store
	writeLog ""
	writeLog "Backup of Jetty keystore"
	writeLog "tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-opt-rsa-jetty9-etc.$timestamp.tar.gz ${JETTYSRV}/keystore ${JETTYSRV}/jetty-ssl.xml"
	tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-opt-rsa-jetty9-etc.$timestamp.tar.gz ${JETTYSRV}/keystore ${JETTYSRV}/jetty-ssl.xml 2>&1 | tee -a $LOG
		syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive Jetty keystore files ${JETTYSRV}"	
}
	
####################################################
## MONGODB INSTANCE
####################################################
function backup_Mongo() {
	local _RESTART
	writeLog "Backup of MongoDB."
	# MongoDB must be running. 
	check_ServiceStatus tokumx init _RESTART && service tokumx start 2>&1  && sleep 10 | tee -a $LOG
	# Lazy solution. If ESA server then temporarily disable auth to dump entire instance. 
	if [ -d /opt/rsa/esa ]; then 
		sed -i "s/\(auth *= *\).*/\1false/" /etc/tokumx.conf 
		service tokumx restart 2>&1 | tee -a $LOG
		sleep 10
	fi

	#Force file synchronization and lock writes
	writeLog "Force file synchronization and lock writes"
	mongo admin --eval "printjson(db.fsyncLock())" 2>&1 | tee -a $LOG
	writeLog "mongodump --out ${BACKUP}/$HOST-mongodb-dump.$timestamp"
	mongodump --out ${BACKUP}/$HOST-mongodb-dump.$timestamp 2>&1 | tee -a $LOG
		syslogOnError ${PIPESTATUS[0]} "SA backup failed to dump the Mongo DB."	
	#Unlock database writes
	writeLog "Unlocking database writes"
	mongo admin --eval "printjson(db.fsyncUnlock())" 2>&1 | tee -a $LOG

	if [ -d /opt/rsa/esa ]; then 
		sed -i "s/\(auth *= *\).*/\1true/" /etc/tokumx.conf 
		service tokumx restart 2>&1 | tee -a $LOG
	fi	

	service tokumx $_RESTART 2>&1 | tee -a $LOG
	
	writeLog "tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-mongodb-dump.$timestamp.tar.gz ${BACKUP}/$HOST-mongodb-dump.$timestamp"
	tar -C ${BACKUP} --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-mongodb-dump.$timestamp.tar.gz $HOST-mongodb-dump.$timestamp 2>&1 | tee -a $LOG
		syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive MongoDB dump."		
	rm -Rf ${BACKUP}/$HOST-mongodb-dump.$timestamp
}	
	
####################################################################
## ESA
# ESASERVER1=/opt/rsa/esa
####################################################################
function backup_ESA() {
	local _RESTART
	writeLog "Backup of ${ESASERVER1}"
	check_ServiceStatus rsa-esa init _RESTART || service rsa-esa stop 2>&1 | tee -a $LOG

	writeLog "tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-opt-rsa-esa.$timestamp.tar.gz $ESASERVER1 --exclude=${ESASERVER1}/lib --exclude=${ESASERVER1}/bin 	--exclude=${ESASERVER1}/geoip --exclude=${ESASERVER1}/db --exclude=${ESASERVER1}/temp --exclude=${ESASERVER1}/client"
	tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-opt-rsa-esa.$timestamp.tar.gz $ESASERVER1 \
		--exclude=${ESASERVER1}/lib \
		--exclude=${ESASERVER1}/bin \
		--exclude=${ESASERVER1}/geoip \
		--exclude=${ESASERVER1}/db \
		--exclude=${ESASERVER1}/temp \
		--exclude=${ESASERVER1}/client 2>&1 | tee -a $LOG
		syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive ESA files ${ESASERVER1}."
		
	service rsa-esa $_RESTART 2>&1 | tee -a $LOG		
} 

####################################################################
## Incident Management
# IM=/opt/rsa/im
####################################################################
function backup_IM() {
	local _RESTART
	writeLog "Backup of ${IM}"
	check_ServiceStatus rsa-im init _RESTART || service rsa-im stop 2>&1 | tee -a $LOG	

	writeLog "tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-opt-rsa-im.$timestamp.tar.gz ${IM} --exclude=${IM}/lib --exclude=${IM}/bin --exclude=${IM}/scripts --exclude=${IM}/db"
	tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-opt-rsa-im.$timestamp.tar.gz ${IM} \
		--exclude=${IM}/lib \
		--exclude=${IM}/bin \
		--exclude=${IM}/scripts \
		--exclude=${IM}/db  2>&1 | tee -a $LOG
		syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive RSA IM files ${IM}."	

		service rsa-im $_RESTART 2>&1 | tee -a $LOG		
} 
 
####################################################################
## RSAMALWARE
# RSAMALWARE=/var/lib/netwitness/rsamalware
####################################################################
function backup_Malware() {
	local _RESTART
	writeLog ""
	writeLog "Backup of ${RSAMALWARE}"
	check_ServiceStatus rsaMalwareDevice upstart _RESTART || stop rsaMalwareDevice 2>&1 && sleep 5 | tee -a $LOG	
	
	writeLog "tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-var-lib-netwitness-rsamalware.$timestamp.tar.gz $RSAMALWARE"
	tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-var-lib-netwitness-rsamalware.$timestamp.tar.gz $RSAMALWARE \
		--exclude=${RSAMALWARE}/jetty/javadoc \
		--exclude=${RSAMALWARE}/jetty/lib \
		--exclude=${RSAMALWARE}/jetty/logs \
		--exclude=${RSAMALWARE}/jetty/webapps \
		--exclude=${RSAMALWARE}/lib \
		--exclude=${RSAMALWARE}/spectrum/yara \
		--exclude=${RSAMALWARE}/spectrum/logs \
		--exclude=${RSAMALWARE}/spectrum/cache \
		--exclude=${RSAMALWARE}/spectrum/temp \
		--exclude=${RSAMALWARE}/spectrum/lib \
		--exclude=${RSAMALWARE}/spectrum/repository \
		--exclude=${RSAMALWARE}/spectrum/infectedZipWatch \
		--exclude=${RSAMALWARE}/spectrum/index \
		--exclude=${RSAMALWARE}/saw 2>&1 | tee -a $LOG
		syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive the RSA Malware files ${RSAMALWARE}."	

		$_RESTART rsaMalwareDevice 2>&1 | tee -a $LOG	
}
  
####################################################################
## LOG COLLECTOR
# LOGCOL=/var/netwitness/logcollector
####################################################################  
function backup_LC() {
	local _RESTART
	writeLog
	writeLog "Backup of ${LOGCOL}"
	check_ServiceStatus nwlogcollector upstart _RESTART || stop nwlogcollector 2>&1  && sleep 5	| tee -a $LOG

	writeLog "tar --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-var-netwitness-logcollector.$timestamp.tar.gz $LOGCOL"
	
    tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-var-netwitness-logcollector.$timestamp.tar.gz $LOGCOL --exclude=$LOGCOL/metadb/core.* 2>&1 | tee -a $LOG
		syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive the Log Collector files ${LOGCOL}."	

	$_RESTART nwlogcollector 2>&1 | tee -a $LOG	
}

####################################################################
## WAREHOUSE CONNECTOR
# WHC=/var/netwitness/warehouseconnector
####################################################################
function backup_WHC() {  
	local _RESTART
	WriteLog
	WriteLog "Backup of ${WHC}"
	check_ServiceStatus nwwarehouseconnector upstart _RESTART || stop nwwarehouseconnector 2>&1 | tee -a $LOG	

	WriteLog "tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-var-netwitness-warehouseconnector.$timestamp.tar.gz $WHC"
    tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-var-netwitness-warehouseconnector.$timestamp.tar.gz $WHC 2>&1 | tee -a $LOG
		syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive the Warehouse connector files ${WHC}."	
	$_RESTART nwwarehouseconnector 2>&1 | tee -a $LOG	
}  

####################################################################
## Operating System configuration files in /etc
# /etc/sysconfig/network-scripts/ifcfg-eth* 
# /etc/sysconfig/network 
# /etc/hosts 
# /etc/resolv.conf 
# /etc/ntp.conf 
# /etc/fstab
# /etc/krb5.conf
#################################################################### 
function backup_etc() { 
    writeLog
    writeLog "Backup of /etc"
    writeLog "tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-etc.$timestamp.tar.gz /etc/sysconfig/network-scripts/ifcfg-eth* /etc/sysconfig/network /etc/hosts /etc/resolv.conf /etc/ntp.conf /etc/fstab /etc/krb5.conf"
    tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-etc.$timestamp.tar.gz /etc/sysconfig/network-scripts/ifcfg-eth* /etc/sysconfig/network /etc/hosts /etc/resolv.conf /etc/ntp.conf /etc/fstab /etc/krb5.conf 2>&1 | tee -a $LOG
		syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive system configuration files."
}

####################################################################
## PUPPET
# PUPPET1=/var/lib/puppet
# PUPPET2=/etc/puppet
####################################################################
function backup_Puppet() {	
	local _RESTART
	writeLog
	writeLog "Backup of Puppet"
	if [ -d "${PUPPET1}" ]; then
		check_ServiceStatus puppetmaster init _RESTART || service puppetmaster stop 2>&1 | tee -a $LOG	

		writeLog "tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-var-lib-puppet-etc.$timestamp.tar.gz ${PUPPET1}/ssl ${PUPPET1}/node_id ${PUPPET2}/puppet.conf ${PUPPET2}/csr_attributes.yaml" 
		tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-var-lib-puppet-etc.$timestamp.tar.gz ${PUPPET1}/ssl ${PUPPET1}/node_id ${PUPPET2}/puppet.conf ${PUPPET2}/csr_attributes.yaml 2>&1 | tee -a $LOG
			syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive the Puppet conf files ${PUPPET1}."	

		service puppetmaster $_RESTART 2>&1 | tee -a $LOG		
	fi;		
}	

####################################################################
## RABBITMQ
# RABBITMQ=/var/lib/rabbitmq
####################################################################
function backup_RabbitMQ() {
	local _RESTART
	writeLog "Backup of RabbitMQ DB - ${RABBITMQ}" 
	check_ServiceStatus rabbitmq-server init _RESTART || service rabbitmq-server stop 2>&1 && sleep 10 | tee -a $LOG	

	writeLog "tar -czvf ${BACKUP}/$HOST-var-lib-rabbitmq.$timestamp.tar.gz ${RABBITMQ}" 
	tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-var-lib-rabbitmq.$timestamp.tar.gz ${RABBITMQ} 2>&1 | tee -a $LOG
		syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive the RabbitMQ files ${RABBITMQ}."	
	# Backup the RabbitMQ configuration
	writeLog "Backup of RabbitMQ Configuration - /etc/netwitness/ng/rabbitmq -> /etc/rabbitmq" 
#	tar -C / --atime-preserve --recursion $TARSWITCHES ${BACKUP}/$HOST-etc-rabbitmq.$timestamp.tar.gz /etc/netwitness/ng/rabbitmq 2>&1 | tee -a $LOG

	service rabbitmq-server $_RESTART 2>&1 | tee -a $LOG	
}

do_Backup() {

	writeLog "Stopping Puppet agent."
	service puppet stop 2>&1 | tee -a $LOG

	for i in "${recipe[@]}"
	do
		$i  
	done
	
	writeLog "Starting Puppet agent."
	service puppet start 2>&1 | tee -a $LOG
	
	writeLog "END $HOST BACKUP"
}

main(){
	writeLog "STARTING $HOST BACKUP"
	mkdir -p ${BACKUP}

	check_root
	check_isRun $SCRIPT_NAME
	rotate_Logs 
#	get_Agrs
	what_to_backup
	do_Backup
#	do_RemoteBackup
	do_Cleanup
}

if [ x"${0}" != x"-bash" ]; then 
	main
	exit 0 
fi
	