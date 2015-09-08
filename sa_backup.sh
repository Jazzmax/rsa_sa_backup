#!/bin/bash
VER=1.0.8
#######################################################################
##
## BACKUP TOOL for RSA Security Analytics 10.3 - 10.5
##
## The script compresses configuration files of all available SA components
## into the backup directory specified in BACKUPPATH.
## Old backups are removed after "n" days specified in RETENTION_DAYS.
##  
##  Author :    Maxim Siyazov 
##  URL:        https://github.com/Jazzmax/rsa_sa_backup
##  License:    GNU General Public License v2 (http://www.gnu.org/licenses/)
##
##  Copyright (C) 2015 Maxim Siyazov
##  This script is distributed in the hope that it will be useful, but WITHOUT
##  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
##  FOR A PARTICULAR PURPOSE. 
##
#######################################################################
# # New in this version 
# 1.0.8		* Fixed a typo in the ESA backup configuration 
# 1.0.7     + Added command line arguments
#           + Added a configuration file to enable/disable backup of components
#           + Added a new option to backup custom user files
#           + Added test mode
#           * Fixed: Cleanup removing non-backup folders
#           * Exclude core files from the Warehouse connector backup 
#           + Added a tar progress indication
#			* Improved reporting engine exlusion list
#			+ Added option to backup only one component
#----------------------------------------------------------------------
# TO DO:
# - Remote backup files 
# - Check if enough disk space to create a backup
# - Encrypt backup file 
# - platform.db to take lobs.db/* or dump the db as per docs

#######################################################################
# Configuration section

BACKUPPATH=/root/sabackups              # Local backup directory
LOG=sa_backup.log                       # The backup log file
LOG_MAX_DIM=10000000                    # Max size of log file in bytes - 10MB 
RETENTION_DAYS=0	                  	# Local backups retention in days (0 - no cleanup)
					
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

# RabbitMQ server
RABBITMQ_ENABLED=true

# Core Appliance Services
CORE_ENABLED=true

# MongoDB 
MONGODB_ENABLED=true

# Malware Analysis
MALWARE_ENABLED=true

# ESA 
ESA_ENABLED=true

# Incident Management
IM_ENABLED=true

# Log collector database
LC_ENABLED=true

# Warehouse Connector database
WHC_ENABLED=true

# PostgreSQL DB
PGSQL_ENABLED=true

# SMS
SMS_ENABLED=true							
					
# Additional/custom folders and files to backup                         
CUSTOM_ENABLED=true
CUSTOM=""
# Exclude list for the custom backup                                
CUSTOM_EXCLUDE=""      

#----------------------------------------------------------------------
	  
# Remote NAS - NOT IMPLEMENTED 
#SSH_HOST=192.168.12.102
#SSH_USERNAME=backup
#REMOTE_DIR=/home/backup/ss_backups
#SSH_IDENTITY_FILENAME=/root/

# Nothing to change below this line
#======================================================================
HOST="$(hostname)"
timestamp=$(date +%Y-%m-%d-%H-%M) 
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_NAME="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
BACKUP="${BACKUPPATH}/${HOST}-${timestamp}"
SYSLOG_PRIORITY=local0.alert
TARVERBOSE=""
PID_FILE=sa_backup.pid

# Colouring output
COL_BLUE="\x1b[34;01m"
COL_GREEN="\x1b[32;01m"
COL_RED="\x1b[31;01m"
COL_YELLOW="\x1b[33;01m"
COL_CYAN="\x1b[36;01m"
COL_RESET="\x1b[39;49;00m"  

COREAPP=/etc/netwitness/ng
NWLOGS=/var/log/netwitness
REPORTING=/home/rsasoc/rsa/soc/reporting-engine
SASERVER1=/var/lib/netwitness/uax
JETTYSRV=/opt/rsa/jetty9/etc
PUPPET1=/var/lib/puppet
PUPPET2=/etc/puppet
MCO=/etc/mcollective
RSAMALWARE=/var/lib/netwitness/rsamalware
ESASERVER1=/opt/rsa/esa
IM=/opt/rsa/im
RSASMS=/opt/rsa/sms
LOGCOL=/var/netwitness/logcollector
RABBITMQ=/var/lib/rabbitmq              # on log collector symlink to /var/netwitness/logcollector/rabbitmq
WHC=/var/netwitness/warehouseconnector
POSTGRESQL=/var/lib/pgsql
TESTMODE=0                              # Test mode	                             
BACKUPONLY=""
declare -A COMPONENT
declare -a ARGS
declare -A COMPONENT_MARKER=( \
	[SYS]="/etc" [CUSTOM]="/tmp/sa_backup_custom" [PUPPET]="/var/lib/puppet" [RABBITMQ]="/var/lib/rabbitmq" \
	[CORE]="/etc/netwitness/ng" [MONGODB]="/etc/init.d/tokumx" [SASERVER]="/var/lib/netwitness/uax" \
	[RE]="/home/rsasoc/rsa/soc/reporting-engine" [MALWARE]="/var/lib/netwitness/rsamalware" \
	[ESA]="/opt/rsa/esa" [IM]="/opt/rsa/im" [LC]="/var/netwitness/logcollector" \
	[WHC]="/var/netwitness/warehouseconnector" [PGSQL]="/var/lib/pgsql" [SMS]="/opt/rsa/sms" )
	
declare -A COMPONENT_BK_FUNCT=( \
	[SYS]="backup_etc" [CUSTOM]="backup_Custom" [PUPPET]="backup_Puppet" [RABBITMQ]="backup_RabbitMQ" \
	[CORE]="backup_CoreAppliance" [MONGODB]="backup_Mongo" [SASERVER]="backup_Jetty" \
	[RE]="backup_RE" [MALWARE]="backup_Malware" \
	[ESA]="backup_ESA" [IM]="backup_IM" [LC]="backup_LC" \
	[WHC]="backup_WHC" [PGSQL]="backup_PostgreSQL" [SMS]="backup_SMS")
										
declare -A COMPONENT_DESC=( \
	[SYS]="OS configuration files" [CUSTOM]="Custom files" [PUPPET]="Puppet master/agent" [RABBITMQ]="RabbitMQ server" \
	[CORE]="Core Appliance Services" [MONGODB]="MongoDB dump" [SASERVER]="SA web server" \
	[RE]="Reporting Engine" [MALWARE]="Malware Analysis" \
	[ESA]="Event Stream Analysis" [IM]="Incident Management server" [LC]="Log Collector database" \
	[WHC]="Warehouse Connector database" [PGSQL]="PostgreSQL database" [SMS]="System Management Server")		
	
CONFIGFILE=""

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
    echo -e "$1" 
}

####################################################################
# If the supplied return value indicates an error, exit immediately
####################################################################
function exitOnError() {
    local RETVAL=$1
    if [ $RETVAL != 0 ]; then
        syslogMessage "SA Appliance Backup Failed [$RETVAL] - Log File: $LOG"
        writeLog ${COL_RED}"$2"${COL_RESET}
        exit 1 # $RETVAL
    fi
}

####################################################################
# If the supplied return value indicates an error, syslog a message but not exit
####################################################################
function syslogOnError() {
    local RETVAL=$1
    if [ $RETVAL != 0 ]; then
        syslogMessage "$2"
        echo -e "${COL_RED}$2 - exit code: [$RETVAL] - Log File: $LOG${COL_RESET}" >&2
        return $RETVAL
    fi
}
####################################################################
# Check is run as root
####################################################################
check_root(){
  if [ "$(id -u)" != "0" ]; then
    writeLog "ERROR: This script must be run as root!"
    exitOnError 1 "ERROR: This script must be run as root!"
  fi
}

####################################################################
## Cleanup the Backup Staging Area
####################################################################
function do_Cleanup {
    if [[ ${RETENTION_DAYS} -ne 0 ]]; then 
        find "${BACKUPPATH}" -maxdepth 1 -name "${HOST}-*" -type d -mtime +${RETENTION_DAYS} -exec rm -Rvf {} \; 2>&1 | tee -a $LOG;
    fi
    rm -rf $PID_FILE ${COMPONENT_MARKER[CUSTOM]}
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
            exitOnError 1 "ERROR: Exit because process sa_backup.sh is already running with pid $OLD_PID"
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
# Check if the SA version is 10.3 or higher (based on Josh Newton's sa_diag)
####################################################################
check_SAVersion() {
    SA_APP_VER_TEMP=`mktemp`
    # Get the (apparent) installed SA version
    SA_APP_TYPE_TEMP=$(rpm -qa --qf '%{NAME}\n' | grep -E '^(nw|jetty|rsa-[a-z,A-Z]*|rsa[m,M]|re-server)' | grep -Ev 'rsa-sa-gpg-pubkeys')
    for SA_PKG_NAME in ${SA_APP_TYPE_TEMP} ; do
        rpm -q "${SA_PKG_NAME}" --qf '%{VERSION}\n' 2> /dev/null >> "${SA_APP_VER_TEMP}"
    done

    SA_RELEASE_VER=$(cat ${SA_APP_VER_TEMP} | grep '^10\.' | sort -Vr | head -n 1)
    rm -f "${SA_APP_VER_TEMP}"
    # Sanity check to make sure version string looks like a version number
    if [ -z "${SA_RELEASE_VER}" ] ; then
       exitOnError 1 "Could not determine appliance type from installed packages. Is this a Security Analytics\nappliance? This tool does not function on NetWitness appliances.\nPlease examine your installed packages.\n"
    fi
    OIFS=$IFS
    IFS='.'
    SA_VER_ARRAY=($SA_RELEASE_VER)
    IFS=$OIFS
    SAMAJOR=${SA_VER_ARRAY[0]}
    SAMINOR=${SA_VER_ARRAY[1]}
    BUILDTYPE=${SA_VER_ARRAY[2]}
    RELEASENUM=${SA_VER_ARRAY[3]}
    writeLog "Found RSA Security Analytics $SAMAJOR.$SAMINOR.$BUILDTYPE" 
    if [[ $SAMAJOR != 10 || !( $SAMINOR =~ ^3|4|5$ ) ]]; then 
        writeLog "SA Backup script can only work on SA version 10.3, 10.4 or 10.5" 
        exitOnError 1 "SA Backup script can only work on SA version 10.3, 10.4 or 10.5"
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
    local __RESTART=""
    [[ "$_SERVICE_TYPE" = "init" ]] && _RETURNVAL=$(service ${_SERVICE} status | grep -E "is running|running_applications" | wc -l);
    [[ "$_SERVICE_TYPE" = "upstart" ]] && _RETURNVAL=$(status ${_SERVICE} | grep "start/running" | wc -l);
    if [ $_RETURNVAL -eq 1 ]; then 
        writeLog "${_SERVICE} is running"
        __RESTART="start"
    else 
        writeLog "${_SERVICE} is not running"
        __RESTART="status"
    fi
    eval $_RESULTVAR="'$__RESTART'"
    return $_RETURNVAL 
}

####################################################################
# Determine components present on the box
####################################################################
function what_to_backup() {
	local i 
	local q
	if [[ -n "$CUSTOM" && "${CUSTOM_ENABLED}" = true ]]; then
		mkdir -p ${COMPONENT_MARKER[CUSTOM]}
	fi
	
    writeLog "The components to back up:"
										
	for i in "${!COMPONENT_MARKER[@]}"; do
		q=${i}"_ENABLED"
		if [ -d "${COMPONENT_MARKER[$i]}" ]; then
			echo -n "- ${COMPONENT_DESC[$i]} " 2>&1 | tee -a $LOG
			if [ "${!q}" = true ]; then 
				COMPONENT+=([$i]="${COMPONENT_BK_FUNCT[$i]}")
				echo 2>&1 | tee -a $LOG
			else
				echo -e ${COL_YELLOW}"Disabled"${COL_RESET}	2>&1 | tee -a $LOG
			fi
		fi		
	done	

	if [ -n "$BACKUPONLY" ]; then
		COMPONENT=([$BACKUPONLY]="${COMPONENT_BK_FUNCT[$BACKUPONLY]}")
		echo -e ${COL_YELLOW}"!!ATTENTION!! --backuponly option is enabled. Will backup the ${COMPONENT_DESC[$BACKUPONLY]} only. Other components will be ignored."${COL_RESET}	
	fi
	
} 

####################################################################
## CORE APPLIANCE SERVICES CONFIGURATION: 
# Log Decoder, Archiver, Decoder, Concentrator, Broker, Log Collector, IPDBExtrator 
# COREAPP=/etc/netwitness/
####################################################################
function backup_CoreAppliance() {
    local _RESTART
    local _SERVICE_RESTART=()
    writeLog "==================================================================="
    writeLog "Backup of Core appliance ${COREAPP}"
    
    writeLog "tar -C / --atime-preserve --recursion -cphzf ${BACKUP}/$HOST-etc-netwitness.$timestamp.tar.gz ${COREAPP}"
    tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-etc-netwitness.$timestamp.tar.gz ${COREAPP} --exclude=${COREAPP}/Geo*.dat --exclude=${COREAPP}/envision/etc/devices --exclude=${COREAPP}/logcollection/content 2>&1 | tee -a $LOG
        syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive Core appliance configuration files ${COREAPP}."
        
}   
####################################################################
# REPORTING ENGINE 
# REPORTING=/home/rsasoc/rsa/soc/reporting-engine
####################################################################
function backup_RE {
    writeLog "==================================================================="
    writeLog "Backup of Reporting Engine ${REPORTING}"
    local EXCL_FILES=''
    local _RESTART
    #Backup only last 2 DB archives. Creating an exclude parameter for old DB archives files   
    for i in $(ls -1tr ${REPORTING}/archives | head -n -2)
      do
        EXCL_FILES+=" --exclude=${REPORTING}/archives/${i}"
      done 

    check_ServiceStatus rsasoc_re upstart _RESTART || stop rsasoc_re 2>&1 | tee -a $LOG
      
    if [ "$RE_FULLBACKUP" -eq 0 ]; then 
        writeLog "Backing up Reporting Engine configuration files..."
        writeLog "tar --atime-preserve --recursion -cphzf ${BACKUP}/$HOST-home-rsasoc-rsa-soc-reporting-engine.$timestamp.tar.gz ${REPORTING}"
            tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-home-rsasoc-rsa-soc-reporting-engine.$timestamp.tar.gz ${REPORTING} \
            --exclude=${REPORTING}/formattedReports \
            --exclude=${REPORTING}/resultstore \
            --exclude=${REPORTING}/livecharts \
            --exclude=${REPORTING}/statusdb \
            --exclude=${REPORTING}/subreports \
            --exclude=${REPORTING}/temp/* \
            --exclude=${REPORTING}/logs \
            ${EXCL_FILES} 2>&1 | tee -a $LOG
            syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive Reporting engine conf files ${REPORTING}."      
    else 
        writeLog "Full Reporting Engine backup enabled."
        writeLog "tar --atime-preserve --recursion -cphzf ${BACKUP}/$HOST-home-rsasoc-rsa-soc-reporting-engine.$timestamp.tar.gz ${REPORTING}"
        tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-home-rsasoc-rsa-soc-reporting-engine.$timestamp.tar.gz ${REPORTING} --exclude=${REPORTING}/temp/* 2>&1 | tee -a $LOG
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
    writeLog "==================================================================="
    writeLog "Backup of SA server: ${SASERVER1}, ${JETTYSRV} and carlos keystore"
    check_ServiceStatus jettysrv upstart _RESTART || stop jettysrv 2>&1  && sleep 5 | tee -a $LOG
    local EXCL_FILES=""
    #Backup only last 2 H2 DB archives. Creating an exclude parameter for old H2 DB archives files   
    for i in $(ls -1tr ${SASERVER1}/db/*.zip | head -n -2)
      do
        EXCL_FILES+=" --exclude=${i}"
      done 
    writeLog "tar -C / --atime-preserve --recursion -cphzf ${BACKUP}/$HOST-var-lib-netwitness-uax.$timestamp.tar.gz ${SASERVER1} ${JETTYSRV}/keystore ${JETTYSRV}/jetty-ssl.xml /opt/rsa/carlos/keystore"        
    tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-var-lib-netwitness-uax.$timestamp.tar.gz ${SASERVER1} \
        ${JETTYSRV}/keystore ${JETTYSRV}/jetty-ssl.xml \
        /opt/rsa/carlos/keystore \
        --exclude=${SASERVER1}/temp \
        --exclude=${SASERVER1}/trustedStorage \
        --exclude=${SASERVER1}/cache \
        --exclude=${SASERVER1}/yum \
        --exclude=${SASERVER1}/logs/*_index \
        --exclude=${SASERVER1}/content \
        --exclude=${SASERVER1}/lib \
        --exclude=${SASERVER1}/scheduler \
        ${EXCL_FILES} 2>&1 | tee -a $LOG
        syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive SA server conf files"   

    $_RESTART jettysrv 2>&1 | tee -a $LOG
    
}
    
####################################################
## MONGODB INSTANCE
####################################################
function backup_Mongo() {
    local _RESTART
    writeLog "==================================================================="
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
    
    writeLog "tar -C ${BACKUP} --atime-preserve --recursion -cphzf ${BACKUP}/$HOST-mongodb-dump.$timestamp.tar.gz $HOST-mongodb-dump.$timestamp"
    tar -C ${BACKUP} --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-mongodb-dump.$timestamp.tar.gz $HOST-mongodb-dump.$timestamp 2>&1 | tee -a $LOG
        syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive MongoDB dump."  
    rm -Rf ${BACKUP}/$HOST-mongodb-dump.$timestamp
}   
    
####################################################################
## ESA
# ESASERVER1=/opt/rsa/esa
####################################################################
function backup_ESA() {
    local _RESTART
    writeLog "==================================================================="  
    writeLog "Backup of ESA server: ${ESASERVER1}"
    check_ServiceStatus rsa-esa init _RESTART || service rsa-esa stop 2>&1 | tee -a $LOG

    writeLog "tar -C / --atime-preserve --recursion -cphzf ${BACKUP}/$HOST-opt-rsa-esa.$timestamp.tar.gz $ESASERVER1 --exclude=${ESASERVER1}/lib --exclude=${ESASERVER1}/bin    --exclude=${ESASERVER1}/geoip --exclude=${ESASERVER1}/db --exclude=${ESASERVER1}/temp --exclude=${ESASERVER1}/client"
    tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-opt-rsa-esa.$timestamp.tar.gz $ESASERVER1 \
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
    writeLog "==================================================================="
    writeLog "Backup of Incident Management: ${IM}"
    check_ServiceStatus rsa-im init _RESTART || service rsa-im stop 2>&1 | tee -a $LOG  

    writeLog "tar -C / --atime-preserve --recursion -cphzf ${BACKUP}/$HOST-opt-rsa-im.$timestamp.tar.gz ${IM} --exclude=${IM}/lib --exclude=${IM}/bin --exclude=${IM}/scripts --exclude=${IM}/db"
    tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-opt-rsa-im.$timestamp.tar.gz ${IM} \
        --exclude=${IM}/lib \
        --exclude=${IM}/bin \
        --exclude=${IM}/scripts \
        --exclude=${IM}/db  2>&1 | tee -a $LOG
        syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive RSA IM files ${IM}."    

        service rsa-im $_RESTART 2>&1 | tee -a $LOG     
} 
 
####################################################################
## RSA SMS 
# RSASMS=/opt/rsa/sms
####################################################################
function backup_SMS() {
    local _RESTART
    writeLog "==================================================================="
    writeLog "Backup of SMS: ${RSASMS}"
    check_ServiceStatus rsa-sms init _RESTART || service rsa-sms stop 2>&1 | tee -a $LOG    

    writeLog "tar -C / --atime-preserve --recursion -cphzf ${BACKUP}/$HOST-opt-rsa-sms.$timestamp.tar.gz ${RSASMS} --exclude=${RSASMS}/lib --exclude=${RSASMS}/bin --exclude=${RSASMS}/scripts --exclude=${RSASMS}/db"
    tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-opt-rsa-sms.$timestamp.tar.gz ${RSASMS} \
        --exclude=${RSASMS}/lib \
        --exclude=${RSASMS}/bin \
        --exclude=${RSASMS}/scripts 2>&1 | tee -a $LOG
        syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive RSA SMS files ${RSASMS}."   

        service rsa-sms $_RESTART 2>&1 | tee -a $LOG        
} 
 
####################################################################
## RSAMALWARE
# RSAMALWARE=/var/lib/netwitness/rsamalware
####################################################################
function backup_Malware() {
    local _RESTART
    writeLog "==================================================================="
    writeLog "Backup of Malware Analysis: ${RSAMALWARE}"
    check_ServiceStatus rsaMalwareDevice upstart _RESTART || stop rsaMalwareDevice 2>&1 && sleep 5 | tee -a $LOG    
    
    writeLog "tar -C / --atime-preserve --recursion -cphzf ${BACKUP}/$HOST-var-lib-netwitness-rsamalware.$timestamp.tar.gz $RSAMALWARE"
    tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-var-lib-netwitness-rsamalware.$timestamp.tar.gz $RSAMALWARE \
        --exclude=${RSAMALWARE}/jetty/javadoc \
        --exclude=${RSAMALWARE}/jetty/lib \
        --exclude=${RSAMALWARE}/jetty/logs \
        --exclude=${RSAMALWARE}/jetty/webapps \
        --exclude=${RSAMALWARE}/jetty/bin \
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
    writeLog "==================================================================="
    writeLog "Backup of Log Collector: ${LOGCOL}"
    check_ServiceStatus nwlogcollector upstart _RESTART || stop nwlogcollector 2>&1  && sleep 5 | tee -a $LOG
    writeLog "This may take long time. Please be patient..." 
    writeLog "tar -C / --atime-preserve --recursion -cphzf ${BACKUP}/$HOST-var-netwitness-logcollector.$timestamp.tar.gz $LOGCOL"
    
    tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-var-netwitness-logcollector.$timestamp.tar.gz $LOGCOL --exclude=$LOGCOL/metadb/core.* 2>&1 | tee -a $LOG
        syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive the Log Collector files ${LOGCOL}." 

    $_RESTART nwlogcollector 2>&1 | tee -a $LOG 
}

####################################################################
## WAREHOUSE CONNECTOR
# WHC=/var/netwitness/warehouseconnector
####################################################################
function backup_WHC() {  
    local _RESTART
    writeLog "==================================================================="
    writeLog "Backup of Warehouse Connector: ${WHC}"
    check_ServiceStatus nwwarehouseconnector upstart _RESTART || stop nwwarehouseconnector 2>&1 | tee -a $LOG   

    writeLog "tar -C / --atime-preserve --recursion -cphzf ${BACKUP}/$HOST-var-netwitness-warehouseconnector.$timestamp.tar.gz $WHC"
    tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-var-netwitness-warehouseconnector.$timestamp.tar.gz $WHC --exclude=$WHC/core.* 2>&1 | tee -a $LOG
        syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive the Warehouse connector files ${WHC}."  
    $_RESTART nwwarehouseconnector 2>&1 | tee -a $LOG   
}  

####################################################################
## Operating System configuration files in /etc
# /etc/sysconfig/network-scripts/ifcfg-*  
# /etc/sysconfig/network 
# /etc/hosts 
# /etc/resolv.conf 
# /etc/ntp.conf 
# /etc/fstab - renamed to fstab.$hostname to prevent overwriting the original fstab on restore
# /etc/krb5.conf
#################################################################### 
function backup_etc() { 
    writeLog "==================================================================="
    writeLog "Backup of OS files /etc"
        
    for file in $(ls -1tr /etc/sysconfig/network-scripts/ifcfg-*[0-9])
    do
        cp -uf  ${file} "${file}.sa_backup"
        sed -e '/^HWADDR=/ s/^#*/#/' -i "${file}.sa_backup"
    done
    
    writeLog "tar -C / --atime-preserve --recursion -cphzf ${BACKUP}/$HOST-etc.$timestamp.tar.gz /etc/sysconfig/network-scripts/ifcfg-*[0-9] /etc/sysconfig/network /etc/hosts /etc/resolv.conf /etc/ntp.conf /etc/fstab /etc/krb5.conf"
    tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE --transform s/.sa_backup// --transform s/fstab/fstab.${HOST}/ -cphzf ${BACKUP}/$HOST-etc.$timestamp.tar.gz /etc/sysconfig/network-scripts/ifcfg-*[0-9].sa_backup /etc/sysconfig/network /etc/hosts /etc/resolv.conf /etc/ntp.conf /etc/fstab /etc/krb5.conf 2>&1 | tee -a $LOG
        syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive system configuration files."
    writeLog "/etc/fstab  was renamed to /etc/fstab.$HOST to prevent overwriting the original /etc/fstab on restore."
    rm -f /etc/sysconfig/network-scripts/ifcfg-*[0-9].sa_backup
}

####################################################################
## MCOLLECTIVE
# MCO=/etc/mcollective
####################################################################
function backup_MCO() { 
    local _RESTART
    writeLog "==================================================================="
    writeLog "Backup of mcollective"
    check_ServiceStatus mcollective init _RESTART || service mcollective stop 2>&1 | tee -a $LOG    

    #writeLog "tar -C / --atime-preserve --recursion -cphzf ${BACKUP}/$HOST-etc-mcollective.$timestamp.tar.gz ${MCO}/ssl ${MCO}/client.cfg ${MCO}/server.cfg" 
    tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-etc-mcollective.$timestamp.tar.gz ${MCO}/client.cfg ${MCO}/server.cfg ${MCO}/ssl 2>&1 | tee -a $LOG
        syslogOnError ${PIPESTATUS[0]} "Failed to archive the mcollective conf files ${MCO}."   

    service mcollective $_RESTART 2>&1 | tee -a $LOG        

}

####################################################################
## PUPPET + MCOLLECTIVE
# PUPPET1=/var/lib/puppet
# PUPPET2=/etc/puppet
####################################################################
function backup_Puppet() {  
    local _RESTART
    writeLog "==================================================================="
    writeLog "Backup of Puppet"
    check_ServiceStatus puppetmaster init _RESTART || service puppetmaster stop 2>&1 | tee -a $LOG  

    writeLog "tar -C / --atime-preserve --recursion -cphzf ${BACKUP}/$HOST-var-lib-puppet-etc.$timestamp.tar.gz ${PUPPET1}/ssl ${PUPPET1}/node_id ${PUPPET2}/puppet.conf ${PUPPET2}/csr_attributes.yaml" 
    tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-var-lib-puppet-etc.$timestamp.tar.gz  ${PUPPET1}  ${PUPPET1}/node_id ${PUPPET2} --exclude=${PUPPET1}/lib --exclude=${PUPPET1}/bucket --exclude=${PUPPET1}/reports  2>&1 | tee -a $LOG
        syslogOnError ${PIPESTATUS[0]} "Failed to archive the Puppet conf files."   

    service puppetmaster $_RESTART 2>&1 | tee -a $LOG
    # backup mcollective
    backup_MCO
}

####################################################################
## RABBITMQ
# RABBITMQ=/var/lib/rabbitmq
####################################################################
function backup_RabbitMQ() {
    local _RESTART
    writeLog "==================================================================="
    writeLog "Backup of RabbitMQ DB: ${RABBITMQ}" 
    check_ServiceStatus rabbitmq-server init _RESTART || service rabbitmq-server stop 2>&1 && sleep 10 | tee -a $LOG    

    writeLog "tar -czvf ${BACKUP}/$HOST-var-lib-rabbitmq.$timestamp.tar.gz ${RABBITMQ}" 
    tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-var-lib-rabbitmq.$timestamp.tar.gz ${RABBITMQ} 2>&1 | tee -a $LOG
        syslogOnError ${PIPESTATUS[0]} "Failed to archive the RabbitMQ files ${RABBITMQ}."  

    # Backup the RabbitMQ configuration for 10.3 
    if [[ ! -h /etc/netwitness/ng/rabbitmq && $SAMINOR -eq 3 ]]; then 
        writeLog "Backup of RabbitMQ Configuration - /etc/rabbitmq" 
        tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-etc-rabbitmq.$timestamp.tar.gz /etc/rabbitmq 2>&1 | tee -a $LOG
    fi 
    service rabbitmq-server $_RESTART 2>&1 | tee -a $LOG    
}
####################################################################
## POSTGRESQL=/var/lib/pgsql
####################################################################
function backup_PostgreSQL() {
    local _RESTART
    writeLog "==================================================================="
    writeLog "Backup of PostgreSQL"
    # in case it is upgraded making an afford to find any version of Postgres
    PGDATA=$(find /etc/init.d/ -name postgresql* -exec cat {} \;  | grep -m 1 "PGDATA=" | sed 's/^PGDATA=//')
    if [[ -z ${PGDATA} ]]; then 
        syslogMessage  1 "Could determine the data directory. PestgreSQL will not be backed up"
        return 1
    fi
    
    if [[ $(find /etc/init.d/ -name postgresql* -exec {} status \; | grep -E "is running|running_applications" | wc -l) -eq 1 ]]; then 
        _RESTART="start"
        find /etc/init.d/ -name postgresql* -exec {} stop \; 2>&1 | tee -a $LOG
    else 
        _RESTART="stop"
    fi
    
    tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-var-lib-pgsql.$timestamp.tar.gz ${PGDATA} 2>&1 | tee -a $LOG
        syslogOnError ${PIPESTATUS[0]} "SA backup failed to archive PostgreSQL database ${PGDATA}."
    
    
    find /etc/init.d/ -name postgresql* -exec {} $_RESTART \; 2>&1 | tee -a $LOG
    
}
####################################################################
## Backup user custom files/folders
####################################################################
backup_Custom(){
    local _EXCL_FILES=""
    writeLog "==================================================================="
    writeLog "Backup Custom files: ${CUSTOM}"

    #Creating an exclude parameter  
    for i in ${CUSTOM_EXCLUDE}
      do
        _EXCL_FILES+=" --exclude=${i}"
      done 
    echo ${CUSTOM} ${_EXCL_FILES}
    writeLog "tar -C / --atime-preserve --recursion -cphzf ${BACKUP}/$HOST-custom-files.$timestamp.tar.gz ${CUSTOM} " 

    tar -C / --atime-preserve --recursion --totals --checkpoint=. $TARVERBOSE -cphzf ${BACKUP}/$HOST-custom-files.$timestamp.tar.gz ${CUSTOM} ${_EXCL_FILES} 2>&1 | tee -a $LOG
        syslogOnError ${PIPESTATUS[0]} "Failed to archive the custom files." 
}

# create a single tarball
create_tarball(){
    local _RETURNVAL
    writeLog "==================================================================="
    writeLog "Creating tarball ${HOST}-${timestamp}.tar"
    tar -C ${BACKUPPATH} --totals --checkpoint=. $TARVERBOSE -cvf ${BACKUPPATH}/${HOST}-${timestamp}.tar --label="The backup of Security Analytics appliance ${SAMAJOR}.${SAMINOR} - ${HOST} taken on ${timestamp}." ${HOST}-${timestamp} 2>&1 | tee -a $LOG    
    _RETURNVAL=${PIPESTATUS[0]}
    syslogOnError ${_RETURNVAL} "SA backup failed to tarball the backup files."
    if [ ${_RETURNVAL} = 0 ];  then 
        writeLog "The backup archive ${BACKUPPATH}/${HOST}-${timestamp}.tar is created"
        writeLog "" 
        rm -fR ${BACKUP}
    fi

    return ${_RETURNVAL}
}

function copy_RemoteSCP()
{
    writeLog "Copying Backup To Remote Location:    [START] " 

    SSH_HOST=$1
    SSH_USERNAME=$2
    REMOTE_DIR=$3
    if [[! -z $4 ]]; then 
        SSH_IDENTITY_FILENAME="-i $4"
    fi
    SOURCE_FILENAME="${BACKUPPATH}/${HOST}-${timestamp}.tar"

    scp -B $SSH_IDENTITY_FILENAME $SOURCE_FILENAME $SSH_USERNAME@$SSH_HOST:$REMOTE_DIR 2>&1 | tee -a $LOG
        exitOnError $? "error"

    writeLog "Copying Backup To Remote Location:    [DONE] "

}


do_Backup() {

    if [[ $SAMINOR -ge 4 ]]; then 
        service puppet stop 2>&1 | tee -a $LOG
    fi
    
    if [[ $TESTMODE -eq 0 ]]; then
        for i in "${COMPONENT[@]}"
        do
            $i
        done
    else
        # Test mode
        writeLog "Test mode: Nothing will be backed up. Exiting."
    fi
    
    if [[ $SAMINOR -ge 4 ]]; then 
        service puppet start 2>&1 | tee -a $LOG
    fi  

}

#########################
# The command line help #
#########################
display_help() {

echo "Usage: $0 [OPTION...]"
echo "BACKUP TOOL for RSA Security Analytics 10.3 - 10.5 - version ${VER}"
echo "sa_backup takes a backup of configurations of Security Analytics components available on the appliance."
echo
echo "Please modify the configuration section in the script or use an external configuration file."
echo 
echo "Examples:"
echo "  sa_backup --config=backup.conf --verbose "
echo 
echo "  sa_backup --backuponly=core "
echo 
echo  "Main operation mode:"
echo 
echo  "-c, --config=CONFIG_FILE      config file"
echo  "-b, --backuponly=COMPONENTS   backup only specified components: "
echo  "                                  core - Core services"
echo  "                                  sys - OS configuration"
echo  "                                  puppet - puppet master/agent configuration"
echo  "                                  rabbitmq - rabbitmq configuration"
echo  "                                  mongo - MongoDB/tokumx dump"
echo  "                                  jetty - SA application server settings"
echo  "                                  re - Reporting Engine "
echo  "                                  malware - Malware Analysis configuration"
echo  "                                  esa - Event Stream Analysis configuration"
echo  "                                  im - Incidint Management configuration"
echo  "                                  sms - System Management System "
echo  "                                  lc - Log collector "
echo  "                                  whc - Warehouse connector" 
echo  "                                  pgqsl - PostgreSQL database"
#echo  "-q, --quite                   quite mode"
#echo  "-i, --interactive             interactive mode"
echo  "-t, --test                    test mode; no backup performed" 
echo  "-v, --verbose                 tar verbose switch"
echo  "-?, -h, --help                give this help list"
echo  

}

get_Args() {
	local i
    for i in "${ARGS[@]}"
        do
            case $i in
                -c=*|--config=*)
                CONFIGFILE="${i#*=}"
				if [ -n "$CONFIGFILE" ]; then
					writeLog "Using the configuration file $CONFIGFILE"
					. "$CONFIGFILE"
				else
					exitOnError 1 'ERROR: "-c|--config" requires a non-empty option argument.'
				fi
                ;;
                -b=*|--backuponly=*)
                BACKUPONLY="${i#*=}"
				if [ -n "$BACKUPONLY" ]; then
					writeLog "Backing up only ${COMPONENT_DESC[$BACKUPONLY]}"
				else
					exitOnError 1 'ERROR: "-b|--backuponly" requires a non-empty option argument.'
				fi
                ;;
                -q|--quite)
                QUITE=1
				writeLog "Quite mode is enabled"
                ;;
                -v|--verbose)
                TARVERBOSE="-v"
				writeLog "TAR verbose mode is enabled"				
                ;;
                -i|--interactive)
                INTERACTIVE=1
				writeLog "Interactive mode is enabled"
                ;;
                -t|--test)
                TESTMODE=1
				writeLog "Test mode is enabled"
                ;;
                -h|-\?|\?|--help)
                display_help
                exit 1
                ;;
                *)
                        # unknown option
                ;;
            esac
        done

}

main(){
    echo -e ${COL_BLUE}"BACKUP TOOL for RSA Security Analytics 10.3 - 10.5 - version ${VER}"${COL_RESET}
    get_Args
    writeLog "STARTING $HOST BACKUP"
    mkdir -p ${BACKUP}
    check_root
    check_isRun $SCRIPT_NAME
    check_SAVersion
    rotate_Logs 
    what_to_backup

    do_Backup
    #create_tarball
    #copy_RemoteSCP 

    do_Cleanup
    writeLog "END $HOST BACKUP"
}

if [ x"${0}" != x"-bash" ]; then 
    ARGS=("$@")
    main
    exit 0 
fi
    