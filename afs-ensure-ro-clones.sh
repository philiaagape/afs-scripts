#!/bin/bash

function usage() {
cat<<ENDUSAGE
Usage: $0 [-print] <fileserver>

Description: checks the named AFS <fileserver> for volumes that don't have a
        "cheap clone" or local RO copy. Then either prints all these volumes
        or runs "vos addsite" for you and releases the volume.

Options:
    -print  Just print the names of volumes that don't have a RO cheap clone

ENDUSAGE

exit
}

[ $# -eq 0 -o "$1" = "--help" -o "$1" = "-h" ] && usage

. /afs/ss2k/system/scripts/afs/afs-helper-functions.sh
afs-system-administrators-check

ONLY_PRINT=0
[ $1 = "-print" ] && { ONLY_PRINT=1; shift; }

SERVER=$1

#save vos listvol output for this server
LISTVOL_OUTPUT_FILE=/tmp/vos-listvol-$SERVER.txt
vos listvol $SERVER > ${LISTVOL_OUTPUT_FILE}
[ $? -ne 0 ] && { echo "ERROR: vos listvol failed."; exit 1; }

#get the total number of volumes from the first line
TOTAL_NUM_VOL=$(grep "^Total number" ${LISTVOL_OUTPUT_FILE} | awk '{print $NF}')
#erase first line
sed -i '/^Total number/d' ${LISTVOL_OUTPUT_FILE}

num_vol=0        #count the number of volumes "fixed"

#read each line from vos listvol, first field is <volume>
cat ${LISTVOL_OUTPUT_FILE} | while read line; do
    #exit on empty line. we are done
    if [ "$line" = "" ]; then
        echo "done. ${num_vol} volumes of ${TOTAL_NUM_VOL} didn't have .readonly"
        exit 0
    fi
    this_line_vol=$(echo ${line} | awk '{print $1}')
    #ignore lines that end with .backup or .readonly
    #- these aren't the RW volumes that we are looking for
    echo ${this_line_vol} | grep -Eq "\.(backup)|(readonly)$" && continue
    #remove .backup and .readonly endings
    base_vol=$(echo ${this_line_vol} |sed -e 's/\.backup$//' -e 's/\.readonly$//')
    #search for base_vol.readonly in the listvol output
    if grep -q "${base_vol}.readonly" ${LISTVOL_OUTPUT_FILE}; then
        #found .readonly
        continue
    else
        #readonly not found!
        ((num_vol++))
        if [ ${ONLY_PRINT} -eq 1 ]; then
            echo ${base_vol}
        else
            vos addsite ${SERVER} a ${base_vol}
            vos release ${base_vol}
        fi
    fi
done
