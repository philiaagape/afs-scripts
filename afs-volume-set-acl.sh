#!/bin/bash
# afs-volume-set-acl.sh
#
# Author: Jonathan Nilsson
# Version: 0.0.2

function short-usage() {
cat<<ENDSHORTUSAGE
Usage: $(basename $0) [-D] [-V]+ [--help] [--clear] [--verify] <mountpoint> [<pts-entry> <permission>]+
ENDSHORTUSAGE
}

function usage() {
cat<<ENDUSAGE|more
$(short-usage)

Description:    Administratively, it is going to be simpler to keep track of
                permissions if we keep them uniform through out an entire 
                volume, rather than individually on each folder.

                This means that if a certain sub-folder needs separate access
                permissions, then a separate volume should be created.
                
                To that end, this tool will traverse a volume and uniformly 
                set the ACL on each folder to the same permissions. The script 
                knows not to traverse a volume mount point or set ACLs on any 
                volume besides the one initially given.

                If the parameter <mountpoint> is just a directory, then the 
                script will find the mount point of that volume and prompt
                you if you meant to set the ACL beginning at that point.

                You can then provide one or more ACL entries in the form of:
                    <pts-entry> <permission>

                Note that the script will always make sure that
                    system:administrators all
                is included in the ACL.

                If you think that the ACL's on subfolders have been modified
                manually and you want to discover any subfolders with 
                mismatched permissions, run the script with '--verify'

                If you find mismatched permissions, you can reset/clear the
                ACL and create it again from scratch with the '--clear' option

Examples:
    $(basename $0) . jnilsson.web write websscs write
    - This would find the volume containing the current directory and add to
      the ACL for that volume the following permissions:
        jnilsson.web write
        websscs write

    $(basename $0) --clear /afs/ss2k/departments/sscsdept sscs-2k write
    - This would clear the ACL's on the sscsdept volume and replace it with:
        sscs-2k write

Author:$(awk -F: '/^# Author/ {print $2}')
Version:$(awk -F: '/^# Version/ {print $2}')
ENDUSAGE

#vim syntax highlighting bug workaround for here-doc pipe to more
ENDUSAGE|more
}

###############################################################################
##
##                         DEFAULT VARIABLES
##
###############################################################################

DO_CLEAR=false
DO_VERIFY=false
INPUTDIR=
declare -a ACL
ACL_I=0


###############################################################################
##
##                           PARSE ARGUMENTS
##
###############################################################################

while [ $# -gt 0 ]; do
    case $1 in
        --help) usage; exit 0; ;;
        --clear) DO_CLEAR=true; ;;
        --verify) DO_VERIFY=true; ;;
        -*) short-usage; exit 1; ;;
        *)  if [ "${INPUTDIR}" = "" ]; then
                INPUTDIR=$1; 
            else
                ACL[ACL_I++]=$1
            fi
            ;;
    esac
    shift
done

cat<<TEST
INPUTDIR=${INPUTDIR}
$(i=0; while [ $i -lt ${#ACL[*]} ]; do
echo "ACL $((i/2)) = ${ACL[i++]}  ${ACL[i++]}";
done)
TEST
exit
###############################################################################
##
##                          VALIDATE INPUT
##
###############################################################################


