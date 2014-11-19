#!/bin/bash
#
# Title: afs-backup-init.sh
#
# Description: Use this script to begin dumping volume sets.
#              It must be run on the Backup/Tape Coordinator.  It will:
#                1) start the 'butc -localauth' process
#                2) determine which volume sets to dump
#                3) determine what dump-level to use
#                4) execute all appropriate "backup dump..." commands
#                5) kill the butc process when finished
#
#              The script can be started via a BOS Cron job, or by root.
#
# Requirements: This script depends on:
#                1) the afs-mount-dumpfile.sh script to automatically
#                   setup the /dev/afs-dump symlink
#                2) a certain naming scheme for volume-sets so that it
#                   can determine which volume sets to dump.
#		    'ro-vol_' is the prefix expected by default.
#
# Author: Jonathan Nilsson, jnilsson@uci.edu
#
# Version: 0.6.1
#

############################ DEFINITIONS ##############################
function usage() {
cat<<EOHELP
USAGE: `basename $0` [OPTIONS]

DESCRIPTION:
     Initialize the AFS backup dump processes. Dump volume sets begining
	with the default or specified prefix at the default or specified
	dump-level.
     The default volume set prefix is 'ro-vol_' and the default dump-level
	is simply the "next" one in the dump schedule. The output of
	'backup listdumps' and 'backup dumpinfo' is used for this.
     In DEBUG mode, output to standard out. If DEBUG > 1, disable dumps

OPTIONS:
	-h	print this usage description
	-D	enable DEBUG mode. repeat to increment.
	--volset-prefix <volset_prefix>
		use <volset_prefix> to search for volume sets to dump
	--dump-level <dump_level>
		use <dump_level> instead of determining automatically
	--dump-prefix <dump_prefix>
		use <dump_prefix> to loop through matching dump-levels
		rather than all dump levels in the schedule

AUTHOR:`awk -F: '/^# Author:/ {print $2}' $0`

VERSION:`awk -F: '/^# Version:/ {print $2}' $0` 
EOHELP
}

# reporting options: mail a logfile to the address, unless DEBUG is non-zero
MAILTO="jnilsson@uci.edu dmvuong@uci.edu"
MAIL_LOG=/tmp/afs-backup-init-mail-log.txt
cat /dev/null > ${MAIL_LOG}
DEBUG=0
FAILED=0
SCRIPT_LOG=/var/log/`basename $0`.log

# VOLSET_PREFIX
#   use to specify which volume sets to dump, volume sets defined
#   in the backup database should use the following prefix
VOLSET_PREFIX="ro-vol_"

# DUMP_LEVEL
#   use to specify what dump level to use.
DUMP_LEVEL=

# AUTO_LEVEL
#   set to 1 by default to auto-determine the next dump level
#   if the option --dump-level is set, then AUTO_LEVEL is set to 0
AUTO_LEVEL=1

# BUTC_PROG
#   location of the butc program
BUTC_PROG="/usr/sbin/butc"

# Backup list/info commands
BACKUP_CMD="/usr/sbin/backup"
LISTDUMPS_CMD="${BACKUP_CMD} listdumps -localauth"
LISTVOLSETS_CMD="${BACKUP_CMD} listvolsets -localauth"
DUMPINFO_CMD="${BACKUP_CMD} dumpinfo -localauth"
DUMP_LIST=(`${LISTDUMPS_CMD} 2>/dev/null`)
FULL_DUMP_LIST=(`${LISTDUMPS_CMD} 2>/dev/null | grep -E "^/"`)

# mecho = "mail echo"
#
# if DEBUG is set to 0, echo to the mail log
#    else echo to standard out
function mecho() {
	if [ ${DEBUG} -eq 0 ]; then
		echo $* >> ${MAIL_LOG}
		echo $* >> ${SCRIPT_LOG}
	else
		echo $*
	fi
}

echo "************ `date` **************" >> ${SCRIPT_LOG}

############################ SANITY CHECKS ############################

[ ${UID} -ne 0 ] && { mecho "must be root!"; exit 1; }

if [ ! -x ${BUTC_PROG} ]; then
	mecho "${BUTC_PROG} not found or not executable"
	exit 1
fi

############################ READ OPTIONS ############################
while [ $# -gt 0 ]; do
	case $1 in
		-D) ((DEBUG++)); ;;
		-h) usage; exit 0; ;;
		--volset-prefix) VOLSET_PREFIX=$2; shift; ;;
		--dump-level) AUTO_LEVEL=0; DUMP_LEVEL=$2; shift; ;;
		--dump-prefix)
			DUMP_LIST=(`${LISTDUMPS_CMD} 2>/dev/null | grep $2`)
			FULL_DUMP_LIST=(`${LISTDUMPS_CMD} 2>/dev/null | grep $2 | grep -E "^/"`)
			if [ ${#FULL_DUMP_LIST[*]} -eq 0 ]; then
				mecho "Dump prefix '$2' resulted in invalid dump hierarchy"
				mecho -F '\n' ${DUMP_LIST[@]}
				exit 1
			fi
			;;
		*) echo "unknown option '$1'"; usage; exit 1; ;;
	esac
	shift
done

############################     MAIN     #############################
mecho "starting dumps at: `date`"
# to be safe, kill and then restart the butc process.
mecho "starting 'butc -localauth'..."
[ $DEBUG -lt 2 ] && /usr/bin/pkill butc > /dev/null 2>&1
[ $DEBUG -lt 2 ] && ${BUTC_PROG} -localauth >> ${SCRIPT_LOG} 2>&1 &
RETVAL=$?
[ $FAILED -eq 0 ] && FAILED=$RETVAL

# generate a backup dump command for each volume set
for volset in `${LISTVOLSETS_CMD} 2>/dev/null | grep ${VOLSET_PREFIX} | cut -d\  -f3 | sed 's/://'`;
do
	# if --dump-level was given, then use it
	if [ ${AUTO_LEVEL} -eq 0 ]; then
		mecho "${BACKUP_CMD} dump ${volset} ${DUMP_LEVEL} -localauth 2>/dev/null"
		[ $DEBUG -lt 2 ] && ${BACKUP_CMD} dump ${volset} ${DUMP_LEVEL} -localauth >> ${SCRIPT_LOG} 2>/dev/null
		RETVAL=$?
		[ $FAILED -eq 0 ] && FAILED=${RETVAL}
		continue
	fi

	# begin AUTO_LEVEL section
	# determine last dump name
	lastdumpname="`${DUMPINFO_CMD} 2>/dev/null | grep ${volset} | tail -n1 | awk '{print $8}'`"
	
	# if there was no last dump, then start at the beginning
	if [ -z "${lastdumpname}" ]; then
		DUMP_LEVEL="${FULL_DUMP_LIST[0]}"
	# otherwise search for the last dump and determine the next dump
	else
		# extract the last dump-level from the dump name
		lastdumplevel=`echo $lastdumpname | cut -d\. -f2`
		# loop the schedule to build the next DUMP_LEVEL
		d_index=0 #all dumps list index
		f_index=0 #only full (level 0) dumps index
		for (( ; $d_index < ${#DUMP_LIST[*]}; ++d_index ));
		do
			# keep track of which full dump "hierarchy branch" we are in
			if [ "${DUMP_LIST[$d_index]}" = "${FULL_DUMP_LIST[$f_index + 1]}" ]; then
				((++f_index))
			fi
			if [ "${DUMP_LIST[$d_index]}" = "/$lastdumplevel" ]; then
				# we found the last dump, so go to the next
				((++d_index))
				# keep track of which full dump "hierarchy branch" we are in
				if [ "${DUMP_LIST[$d_index]}" = "${FULL_DUMP_LIST[$f_index + 1]}" ]; then
					((++f_index))
				fi
				# check if we need to loop back to the first dump
				[ $d_index -eq ${#DUMP_LIST[*]} ] && { d_index=0; f_index=0; }
				# check if the next dump is a full dump
				if [ "${DUMP_LIST[$d_index]}" = "${FULL_DUMP_LIST[$f_index]}" ]; then
					DUMP_LEVEL="${FULL_DUMP_LIST[$f_index]}"
				else
					DUMP_LEVEL="${FULL_DUMP_LIST[$f_index]}${DUMP_LIST[$d_index]}"
				fi
				break
			fi
		done
	fi

	mecho "${BACKUP_CMD} dump ${volset} ${DUMP_LEVEL} -localauth 2>/dev/null"
	[ $DEBUG -lt 2 ] && ${BACKUP_CMD} dump ${volset} ${DUMP_LEVEL} -localauth >> ${SCRIPT_LOG} 2>/dev/null
	RETVAL=$?
	[ ${FAILED} -eq 0 ] && FAILED=${RETVAL}

done

# save the backup database
mecho "${BACKUP_CMD} savedb -localauth 2>/dev/null"
[ $DEBUG -lt 2 ] && ${BACKUP_CMD} savedb -localauth >>${SCRIPT_LOG} 2>/dev/null

mecho "stopping 'butc -localauth'..."
[ ${DEBUG} -lt 2 ] && /usr/bin/pkill butc >> ${SCRIPT_LOG} 2>&1
mecho "finished dumps at: `date`"
mecho "see logfile for details: `echo ${SCRIPT_LOG}`"

SUBJECT="`hostname` - `[ ${FAILED} -eq 0 ] && echo "SUCCESS" || echo "FAILED"` afs backup dumps"
if [ ${DEBUG} -eq 0 ]; then
	cat ${MAIL_LOG} | mail -s "${SUBJECT}" ${MAILTO}
else
	mecho ${SUBJECT}
fi
echo "************ `date` **************" >> ${SCRIPT_LOG}
