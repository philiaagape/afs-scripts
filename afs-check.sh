#!/bin/bash
#
# Title: afs-check.sh
#
# Author: Jonathan Nilsson, jnilsson@uci.edu
#
# Version: 0.8.9
#

function usage() {
cat<<EOHELP
Usage: `basename $0` <mode> [<mode options>]

Description:    This script can perform many different checks on AFS.
        It operates on top of other the other AFS command suites to
        provide a summary or reporting of the various components.

        A required <mode> argument describes what components to check:

         * quota
         * partinfo
         * servinfo
         * volinfo

        See OPERATION MODES below for more details.

OPERATION MODES

    quota       In this mode, check the quota of volumes. Default output is
                just a list of volumes above the warning and critical levels.

                Obtain additional output with '--long' or '--total-usage'

                Options
                -w,--warn <integer>    Set warning level to <integer>%.
                                       Default 80%
                -c,--crit <integer>    Set critical level to <integer>%.
                                       Default 95%
                -a,--all               Display all volume quotas
                -t,--total-usage       Display only the total usage information

    partinfo    In this mode, report on the AFS fileserver partition usage.
                Output is based on "vos partinfo" but converted to human 
                readable numbers and percentages.

    servinfo    In this mode, display information about the number of volumes
                per server. Output is based on 'vos listvldb' and 'vos listvol'

    volinfo     In this mode, search through the VLDB to find volumes in a
                non-standard state. Show:
                 * "lonely" volumes that are unreplicated
                 * locked volumes
                 * unreleased volumes
                
        
Author:`awk -F: '/^# Author:/ {print $2}' $0`

Version:`awk -F: '/^# Version:/ {print $2}' $0` 

EOHELP
}

HELPER_FUNCTIONS="/afs/ss2k/system/scripts/afs/afs-helper-functions.sh"
[ -r ${HELPER_FUNCTIONS} ] && source ${HELPER_FUNCTIONS} || \
{ echo "ERROR: couldn't read file '${HELPER_FUNCTIONS}'"; echo "Check that you have AFS tokens"; exit 1; }

#######################################################################
#
#                       Define Defaults
#
#######################################################################

WARN_LEVEL=80
CRIT_LEVEL=95
TMP_OUT_FILE=/tmp/afs-check.out


function convertKtoG() {
    result=$(echo "scale=2; $1 / ( 1024 * 1024 )" | bc)
    [ "${result:0:1}" = "." ] && echo -n "0"
    echo $result
}


#######################################################################
#
#                     Mode Function Definitions
#  1) quota    - report volumes over "warn" and "crit" level of usage
#  2) partinfo - report fileserver parition usage
#  3) servinfo - report number of volumes per server
#  4) volinfo  - not yet implemented. check vldb and report volume info
#
#######################################################################

function do_quota() {
    
    SHOW_ALL=false
    DO_TOTAL=false
    PATTERN="."
    
    # read quota options
    while [ $# -gt 0 ]; do
        case $1 in
            -w|--warn) WARN_LEVEL=$2; shift; ;;
            -c|--crit) CRIT_LEVEL=$2; shift; ;;
            -a|--all) SHOW_ALL=true; ;;
            -t|--total-usage) DO_TOTAL=true; ;;
            -*) echo "ERROR in 'quota' operation: unknown option '$1'"; exit 1; ;;
            *) PATTERN=$1; ;;
        esac
        shift
    done

    # get list of (matching) volumes, and 
    for thisvol in $(vos listvldb 2>/dev/null|grep ^[dswru]|grep ${PATTERN}); do
        #read diskused and maxquota variables
        eval $(vos exa ${thisvol} -format 2>/dev/null | sed -r -e '/diskused|maxquota/!d' -e 's/\t+/=/')
        used_percent=${maxquota}
        if [ ${maxquota} -gt 0 ]; then
            used_percent=$((${diskused}*100/${maxquota}))
        fi
        if [ "$SHOW_ALL" = "true" -o ${used_percent} -ge ${WARN_LEVEL} ]; then
            cat<<ENDVOLQUOTAINFO
${thisvol} $(convertKtoG ${diskused})/$(convertKtoG ${maxquota}) GB ${used_percent}%
ENDVOLQUOTAINFO
        fi
    done
}

function do_partinfo() {

    for thisserver in $(vos listaddr 2>/dev/null); do
        for partname in $(vos listpart $thisserver | grep "/vicep"); do
            #partinfo is an array = (total free used) #in KB
            partinfo=($(vos partinfo ${thisserver} ${partname} 2>/dev/null|awk '{print $12 " " $6}'))
            partinfo[2]=$((${partinfo[0]}-${partinfo[1]}))
            echo "${thisserver}:${partname} - Used GB: $(convertKtoG ${partinfo[2]}) / $(convertKtoG ${partinfo[0]}) ( $((${partinfo[2]}*100/${partinfo[0]}))% )"
        done
    done
}

function do_servinfo() {

    for thisserver in $(vos listaddr 2>/dev/null); do
        cat<<ENDVOLINFO
******************** ${thisserver} ***********************
$(vos listvldb -server ${thisserver} 2>/dev/null | grep ^Total)
$(vos listvol -server ${thisserver} 2>/dev/null | grep ^Total)
ENDVOLINFO
    done
}

function do_volinfo() {
    echo "not yet implemented"
    exit 0
    
    echo "Volume Information: $(date)" > ${TMP_OUT_FILE}

    if [ $(vos listvldb -locked 2>/dev/null | tail -n1 | awk '{print $3}') -gt 0 ]; then
        echo "******** Locked Volumes ********" >> ${TMP_OUT_FILE}
        vos listvldb -locked >> ${TMP_OUT_FILE} 2>/dev/null
        echo "********** END Locked **********" >> ${TMP_OUT_FILE}
    fi
    num_bad=0
    for thisvol in $(vos listvldb 2>/dev/null|grep ^[a-z]); do
        vos examine ${thisvol} -format 2>/dev/null | while read volstat; do
            echo $volstat | grep "^status" | grep -q OK
            if [ $? -ne 0 ]; then
                ((num_bad++))
                vos examine ${thisvol} -format 2>/dev/null >> ${TMP_OUT_FILE}
                echo "*****************************" >> ${TMP_OUT_FILE}
            fi
        done
    done

    echo "Total non-OK Volumes: ${num_bad}" >> ${TMP_OUT_FILE}
    cat ${TMP_OUT_FILE} | less
}

#######################################################################
#
#                   Authentication and Validation Checks
#
#######################################################################

#print usage if no arguments given
[ $# -eq 0 -o $1 = "-h" -o $1 = "--help" ] && { usage; exit 0; }

#afs-system-administrators-check

#######################################################################
#
#                       MAIN
#
#######################################################################

case $1 in
    quota) shift; do_quota $@; ;;
    partinfo) shift; do_partinfo $@; ;;
    servinfo) shift; do_servinfo $@; ;;
    volinfo) shift; do_volinfo $@; ;;
    *) echo "ERROR: unkown mode '$1'"; exit 1; ;;
esac

