#!/bin/bash
# afs-release-volumes.sh
#
# Author: Jonathan Nilsson, jnilsson@uci.edu
# Version: 0.8.1


function usage() {
cat<<ENDUSAGE
 Usage: afs-release-volumes.sh [-D] [-s <server>] [-p <partition>] [pattern]
 
 Description: release all AFS volumes, or optionally release only volumes whose
              names match the given pattern.

 Options:
    -D      Debug; don't do anything, just list what would be done
    --all   Release all volumes without prompting. Otherwise it will 
            warn and prompt for confirmation.
    -server <server-pattern>
    -partition <partition-pattern>
            Match only volumes on a certain server. This is useful if you want
            to avoid putting load on certain servers.
            You can optionally specify a particular partition. 
 Version: $(cat $0|awk '/^# Version:/ {print $3}')
ENDUSAGE
}

############################### DEFAULTS ###################################
LOGFILE=/var/log/`basename $0`.log
DEBUG=0
SERVER=
PARTITION=
VOL_PATTERN=.
LOCALAUTH=

############################ SETUP LOCALAUTH ###############################
# root is allowed to run, with -localauth flag
# besides root, only AFS system:administrators will be able to release volumes
[ ${UID} -eq 0 -a -r /usr/afs/etc/KeyFile ] && LOCALAUTH="-localauth"

############################### READ ARGS ##################################
if [ $# -eq 0 ]; then
    read -p "About to release ALL volumes. OK? [y|N] " all_ok
    [ "$all_ok" = "y" ] || exit;
fi

while [ $# -gt 0 ]; do
	case $1 in
        -h|--help) usage; exit; ;;
        --all) DO_ALL=1; ;;
		-D) DEBUG=1; ;;
		-s*) SERVER="-server $2"; shift; ;;
		-p*) PARTITION="-partition $2"; shift; ;;
        -*) echo "ERROR: unknown option '$1'"; usage; exit 1; ;;
		*) VOL_PATTERN=$1; ;;
	esac
	shift
done

################################# MAIN ####################################
[ ${DEBUG} -eq 0 -a $UID -eq 0 ] && exec >> ${LOGFILE}
[ ${DEBUG} -ne 0 ] && echo "DEBUG MODE ENABLED"

echo "*******************************"
echo -n "starting volume release at: "
date

for vol in `vos listvldb ${SERVER} ${PARTITION} -quiet ${LOCALAUTH} | grep -E "^[a-z]" | grep -E "${VOL_PATTERN}"`; do
	echo "vos release $vol ${LOCALAUTH}"
	[ ${DEBUG} -eq 0 ] && vos release $vol ${LOCALAUTH}
done

echo -n "finished volume release at: "
date
