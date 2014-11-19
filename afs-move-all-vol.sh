#!/bin/bash
#
# Description: move volumes (all or 'matching' volumes) from one server to another
#
# Author: Jonathan Nilsson
#
# Version: 1.0.3
#

function shortusage() {
cat<<ENDSHORTUSAGE
Usage: `basename $0` [-D] [-v] [-ro] [pattern] <from-server> <from-partition> <to-server> <to-partition>

Use "`basename $0` --help" for a longer description
ENDSHORTUSAGE
    exit 0
}

function usage() {

    cat<<ENDUSAGE

Usage: `basename $0` [options] [pattern] <from-server> <from-partition> <to-server> <to-partition>

Description: a 'pattern' can be given to match desired volumes to be moved. 'pattern' is
     a regular expression and must be single quoted to avoid shell glob matches.
     Otherwise, all volumes will be moved.

Options:
    -ro    Also move the RO clone (actually, it removes the original and creates a new clone)
     -v    Increase verbosity
     -D    Turn on Debug mode. Don't actually do anything, just show what would be done.

Required arguments:
     <from-server> <from-partition> <to-server> <to-partition>

     The server arguments can be a full hostname or a short hostname if it resolves
     to the full hostname.

     The partition arguments can be either the full name - like "/vicepa" or "/vicepb" -
     or just the single identifying character - like "a" or "b"

Examples:
     `basename $0` athens a dublin a
         - move all volumes from server athens, partition /vicepa
             to server dublin, partition /vicepa
     `basename $0` '^web' cairo b berlin /vicepb
         - move all volumes matching the pattern "^web" (begins with "web")
             from server cairo /vicepb to berlin /vicepb

Author: `awk -F: '/^# Author:/ {print $2}' $0`
Version: `awk -F: '/^# Version:/ {print $2}' $0`
ENDUSAGE
    exit 0
}

[ "$1" = "--help" -o "$1" = "-h" ] && usage

#Read helper functions
HELPER_FUNCTIONS="/afs/ss2k/system/scripts/afs/afs-helper-functions.sh"
[ -r ${HELPER_FUNCTIONS} ] && . ${HELPER_FUNCTIONS}

######################################################################
#
#                        AUTHENTICATION CHECK
#
######################################################################

afs-system-administrators-check

[ $# -lt 4 ] && shortusage

######################################################################
#
#                        READ OPTIONS 
#
######################################################################
VERBOSITY=0
DEBUG=0
PATTERN=
ARG_N=0
ALSO_RO=false

# this array will hold the values:
# (<from-server> <from-partition> <to-server> <to-paritition>)
declare -a FROM_TO_SERVER

while [ $# -gt 0 ]; do 
    case $1 in
        -ro) ALSO_RO=true; ;;
        -v) ((VERBOSITY++)); ;;
        -D) DEBUG=1; VERBOSITY=9; ;;
        -*) usage; ;;
        *)
            if [ $# -eq 5 ]; then
                PATTERN=$1
            else
                FROM_TO_SERVER[ARG_N++]=$1
            fi
            ;;
    esac
    shift
done

# Error checking: did they input all required arguments?
if [ $ARG_N -ne 4 ]; then
    echo "ERROR: you did not input all the required arguments."
    if [ $VERBOSITY -gt 0 ]; then
        echo "REQUIRED:"
        echo "FROM SERVER=${FROM_TO_SERVER[0]}"
        echo "FROM PARTITION=${FROM_TO_SERVER[1]}"
        echo "TO SERVER=${FROM_TO_SERVER[2]}"
        echo "TO PARTITION=${FROM_TO_SERVER[3]}"
        echo
        echo "OPTIONAL:"
        echo "PATTERN=${PATTERN}"
    fi
    exit 1
fi



######################################################################
#
# DO THE WORK - get list of volumes, filter them, move them
#
######################################################################

for VOLUME in $(vos listvldb -server ${FROM_TO_SERVER[0]} -partition ${FROM_TO_SERVER[1]} | egrep "${PATTERN:-^[a-z]}"); do
    if [ ${ALSO_RO} = "true" ]; then
        #if we want to move RO volumes too:
        # first check that the RO exists on the from-server/from-partition:
        vos exa ${VOLUME} 2>&1 | grep -q "${FROM_TO_SERVER[0]}.*partition.*${FROM_TO_SERVER[1]}.*RO"
        if [ $? -eq 0 ]; then
            #remove the old site from the VLDB
            run vos remove ${FROM_TO_SERVER[0]} ${FROM_TO_SERVER[1]} ${VOLUME}.readonly
            #add the new site
            run vos addsite ${FROM_TO_SERVER[2]} ${FROM_TO_SERVER[3]} ${VOLUME}
        fi
    fi
    run vos move ${VOLUME} ${FROM_TO_SERVER[0]} ${FROM_TO_SERVER[1]} ${FROM_TO_SERVER[2]} ${FROM_TO_SERVER[3]} 
    #release the volume to the new site
    run vos release ${VOLUME}  
done
