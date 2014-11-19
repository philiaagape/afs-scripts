#!/bin/bash
#
# TITLE: afs-mount-dumpfile.sh
#
# DESCRIPTION: Automated AFS Backup MOUNT and UNMOUNT script
#
#              When called with MOUNT:
#                    1) mount the NFS server to store the dumpfile
#                    2) generate the dumpfile name
#                    3) create a symlink to the dumpfile
#              When called with UNMOUNT:
#                    1) remove the symlink
#                    2) unmount the NFS share
#
#              Log messages to /var/log/mount-afs-dumpfile.log
#              
#              Call this script from with the /usr/afs/backup/CFG_<device name> file like this:
#                  MOUNT /usr/afs/backup/mount-afs-dumpfile.sh
#                  UNMOUNT /usr/afs/backup/mount-afs-dumpfile.sh
#
# CUSTOMIZATION: All that needs to be specified are the three DEFAULT_ variables related to NFS
#
# AUTHOR: Jonathan Nilsson, jnilsson@uci.edu
#
# VERSION: 0.9.4
#

###################### DEFAULTS ######################
DEFAULT_MOUNTPOINT=/mnt/afsdump
DEFAULT_NFS_SERVER=rdsan.ss.uci.edu
DEFAULT_NFS_SHARE=afsdump
LOG_FILE=/var/log/`basename $0`.log

# echo and log a message
# an optional second parameter [0|1] means:
# 0 - just echo the message
# 1 - just log the message
function echo-n-log() {
	[ $# -eq 1 -o "v$2" = "v0" ] && echo "$1"
	[ $# -eq 1 -o "v$2" = "v1" ] && echo "$1" >> ${LOG_FILE}
}

function generate-log() {
	echo "**** `date` ****" >> ${LOG_FILE}
	echo "DEVICE_FILE=${DEVICE_FILE}" >> ${LOG_FILE}
	echo "OPERATION=${OPERATION}" >> ${LOG_FILE}
	echo "TRIES=${TRIES}" >> ${LOG_FILE}
	echo "TAPE_NAME=${TAPE_NAME}" >> ${LOG_FILE}
	echo "TAPE_ID=${TAPE_ID}" >> ${LOG_FILE}
	echo "DUMP_FILE_NAME=${DUMP_FILE_NAME}" >> ${LOG_FILE}
}

###################### READ ARGS #####################
DEVICE_FILE=$1
OPERATION=$2
TRIES=$3
TAPE_NAME=$4
TAPE_ID=$5

# generate the dump-file name from the tape name
DUMP_FILE_NAME=`echo ${TAPE_NAME} | awk -F\. '{print $1 "-" $2}'`

#################### VERIFY OPERATION #########################
[ $UID -ne 0 ] && { echo-n-log "cannot be run as non-root users"; exit 2; }

case ${OPERATION} in
	unmount)
		generate-log
		[ -L ${DEVICE_FILE} ] && rm -f ${DEVICE_FILE}
		umount ${DEFAULT_MOUNTPOINT}
		exit 0
		;;
	restore|dump|savedb)
		generate-log
		;;
	*)
		generate-log
		echo-n-log "`basename $0` - called with unsupported operation:" 
		echo-n-log "    '${OPERATION}'"
		exit 2
		;;
esac
	
#################### SANITY CHECKS ####################
# 1) if TAPE_NAME or TAPE_ID are blank, then we 
#    won't be able to automatically determine the filename to use.
#    return exit code 2 to require manual intervention.
# 2) if TRIES is more than 3, exit 2 to require manual intervention
# 3) if DEVICE_FILE already points to DUMP_FILE_NAME,
#    then we don't need to do anything

if [ -z "${TAPE_NAME}" -o -z "${TAPE_ID}" ]; then
	echo-n-log "tape name or id is blank. specify which data-file to read"
	exit 2
fi

[ $TRIES -gt 3 ] && { echo-n-log "too many tries; exiting."; exit 2; }

if [ -f ${DEVICE_FILE} ] && ( file -b ${DEVICE_FILE} | grep -qE "^symbolic link to .*${DUMP_FILE_NAME}" ); then
	echo-n-log "${DEVICE_FILE} already correctly points to ${DUMP_FILE_NAME}" 1
	exit 0
else
	# if DEVICE_FILE is a symbolic link, remove it so we can create a new/correct link
	if [ -L ${DEVICE_FILE} ]; then
		echo-n-log "${DEVICE_FILE} points to incorrect dumpfile; removing..." 1
		rm -f ${DEVICE_FILE}
	elif [ -s ${DEVICE_FILE} ]; then
		echo-n-log "${DEVICE_FILE} is a non-empty file; unable to proceed."
		echo-n-log "Please manually setup ${DEVICE_FILE} as a symlink pointing to the dumpfile ${DUMP_FILE_NAME}."
		exit 2
	else
		echo-n-log "Removing empty file ${DEVICE_FILE} and setting up symlink." 1
	fi
fi

################## MOUNT THE NFS SERVER #######################
############### OR CHECK IF ALREADY MOUNTED ###################
RETVAL=0
echo-n-log "mount -t nfs ${DEFAULT_NFS_SERVER}:/${DEFAULT_NFS_SHARE} ${DEFAULT_MOUNTPOINT}" 1
mount -t nfs ${DEFAULT_NFS_SERVER}:/${DEFAULT_NFS_SHARE} ${DEFAULT_MOUNTPOINT} >> ${LOG_FILE} 2>&1
RETVAL=$?

if [ $RETVAL -eq 0 ]; then
	echo-n-log "mounting succeeded" 1
elif [ $RETVAL -eq 32 ]; then
	echo-n-log "'${DEFAULT_NFS_SERVER}:/${DEVAULT_NFS_SHARE}' is already mounted at ${DEFAULT_MOUNTPOINT}" 1
else
	echo-n-log "mounting FAILED; exit code ${RETVAL}."
	exit ${RETVAL}
fi

#################### CREATE THE SYMLINK #######################
ln -s ${DEFAULT_MOUNTPOINT}/${DUMP_FILE_NAME} ${DEVICE_FILE}
RETVAL=$?

echo-n-log "ln -s ${DEFAULT_MOUNTPOINT}/${DUMP_FILE_NAME} ${DEVICE_FILE}" 1
echo-n-log "exit code ${RETVAL}" 1
