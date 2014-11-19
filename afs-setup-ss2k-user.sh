#!/bin/bash
#
# Title: afs-setup-ss2k-user.sh
#
# Author: Jonathan Nilsson, jnilsson@uci.edu
#
# Version: 1.5.6
#
# 
function short_usage() {
cat<<SHORT_HELP
Usage: `basename $0` [-h] [-D] [-v] [--verify] [--reset-perms]
    [-G <groupname>]+ [-q <gigabytes>] [--transfer] [-p]
    <username>

Try "`basename $0` --help" for more details.
SHORT_HELP
exit 1
}

function usage() {
cat<<EOHELP|more
Usage: `basename $0` [options] <username>

Description: This script expects a user to already be created in
    Active Directory. It can then:
      * Create a PTS user and group(s)
      * Add the user to PTS groups
      * Create the 'users.<username>' Volume for the home dir
      * Create 'users.<username>.pub' Volume for public_html
      * Set the User Volume's Quota
      * Add replication sites for created volumes
      * Make the RW mountpoint
      * Setup ACLs and ownership
      * Release the volume clones
      * Transfer the data from NAS to AFS

    The script will attempt to perform each of the necessary actions
    depending on the Options specified. It is designed so that it can be
    safely rerun on an existing account, for example to change the quota
    or update Group membership.

Options:
    -D  Enable Debuging, turn verbosity to highest,
        and don't actually do anything.
    -G <groupname>
        Setup group membership based on named group    
        Repeat to add to multiple groups
    -h  Print this usage message and exit
    --verify
        Just verify the status of a user account. This option will
        print the following information:
            * AFS Volume name
            * AFS Volume mount point
            * AFS Volume Quota
            * Groups that the user is a member of
            * AD profile home directory
            * AD unix home directory
    -p  Setup the home directory with public_html
    -q <gigabytes>
        Specify the quota to assign in <gigabytes>.
        NOTE: this quota is also used for the public_html volume if -p is used.
    --reset-perms
        Reset the AFS ACL permissions on the home directory.
        If you need to reset the permissions on the public_html,
        then include the '-p' option too.
    -s <fileserver>
        Setup new volumes on the specified AFS <fileserver> instead of
        using the default: ${HOME_FS}
    --transfer
        Transfer their home directory data from the NAS to AFS
    -v  Increase verbosity; repeat to increase again.

Examples:
    Setup a new AFS account, include a public_html folder, and set the quota
    to the default for 'Faculty':
        $(basename $0) -p -q 3 flastnam
    
    Transfer the files from the NAS to AFS for an already created account:
        $(basename $0) --transfer aaccount

    Increase the quota to 12GB and add a public_html for user 'adiskhog':
        $(basename $0) -q 12 -p adiskhog

Author:`awk -F: '/^# Author:/ {print $2}' $0`

Version:`awk -F: '/^# Version:/ {print $2}' $0` 

EOHELP
exit 0

#a vim bug does not recognize the above EOHELP as the end of the here-doc
#so i have inserted the line below to correct the syntax highlighting.
#the above exit 0 command should prevent any run-time errors
#(though technically this EOHELP|more is a syntax error).
EOHELP|more
exit 1
}

[ "$1" = "-h" ] && short_usage
[ "$1" = "--help" ] && usage

####################################################################
#
#                      SET DEFAULTS 
#
####################################################################

BACKUP_FS=afsro1.ss2k.uci.edu
BACKUP_PART=/vicepa
HOME_FS=casablanca
HOME_PART=/vicepa
HOME_SKEL=/etc/skel
APACHE_USER=apache-services
WEBSERVER_MACHINES=host-webserver_ips

#Read helper functions: afs-system-administrators-check and run
#HELPER_FUNCTIONS="/afs/ss2k/users/j/jnilsson/myrepo/afs/afs-helper-functions.sh"
HELPER_FUNCTIONS="/afs/ss2k.uci.edu/system/scripts/afs/afs-helper-functions.sh"
if [ -r ${HELPER_FUNCTIONS} ]; then
    source ${HELPER_FUNCTIONS}
else
    echo "ERROR: unable to read necessary AFS helper functions"
    echo "Verify access to '${HELPER_FUNCTIONS}'"
    exit 1
fi

######################################################################
#
#                        AUTHENTICATION CHECK
#
######################################################################

#checks if running user has tokens and is a member of system:administrators
afs-system-administrators-check

######################################################################
#
#                        READ OPTIONS 
#
######################################################################

[ $# -eq 0 ] && \
{ echo "Error: You must supply at least a <username>!"; \
    short_usage; }

DEBUG=0
VERBOSITY=0
SET_QUOTA=-1
DO_TRANSFER=no
RESET_PERMS=no
SET_QUOTA=-1
PUB_QUOTA=-1
SETUP_PUBLIC_HTML=0
declare -a ADD_GROUPS
GRP_I=0
USERNAME=
JUST_VERIFY=no
#if any of the "change" commands succeed below, then this is set to yes
RELEASE_NEW=no

while [ $# -gt 0 ]; do
    case $1 in
        --transfer) DO_TRANSFER=yes; ;;
        -D) ((DEBUG++)); VERBOSITY=9; ;;
        -G) ADD_GROUPS[GRP_I++]=$2; shift; ;;
        --verify) JUST_VERIFY=yes; ;;
        -p) SETUP_PUBLIC_HTML=1; ;;
        -q|--quota)
            if [ $2 -eq 0 ]; then
                echo "WARNING: You are setting a no-limit quota!"
                read -p "Confirm that this is what you want to do?[y|N] " confirm_quota
                [ "${confirm_quota}" = "y" ] || exit
            elif [ $2 -gt 20 ]; then    
                echo "WARNING: You are attempting to set a quota larger than 20GB"
                read -p "Confirm that this is what you want to do?[y|N] " confirm_quota
                [ "${confirm_quota}" = "y" ] || exit
            fi
            SET_QUOTA=$((1024*1024*$2))
            PUB_QUOTA=$2
            shift
            ;;
        --reset-perms) RESET_PERMS=yes; ;;
        -s) HOME_FS=$2; shift; ;;
        -v) ((VERBOSITY++)); ;;
        -*) echo -e "ERROR: unknown option \"$1\"\n"; short_usage; ;;
        *) USERNAME=$1; ;;
    esac
    shift
done

######################################################################
#
#                        SANITIZE INPUT
#
######################################################################

[ -z ${USERNAME} ] && { echo -e "ERROR: missing <username> argument!\n"; short_usage; }
USER_ID=`id -u ${USERNAME} 2>/dev/null`
[ $? -ne 0 ] && { echo "ERROR: Non-existent user: ${USERNAME}"; \
echo "Please create the user in Active Directory first!"; exit 1; }

INITIAL=`echo ${USERNAME} | sed 's/^\(.\).*$/\1/'`
HOME_DIR_RW=/afs/.ss2k.uci.edu/users/${INITIAL}/${USERNAME}

#if DO_TRANSFER, then
# 1) must be root 
# 2) check if public_html exists but "-p" option was not given
if [ "${DO_TRANSFER}" = "yes" ]; then
    #need to be root and have access to /u/nas/<username>
    [ ${EUID} -eq 0 ] || \
    { echo "ERROR: you are not root. Unable to perform transfer."; exit 1; }
    # check for public_html
    [ -d /u/nas/${USERNAME}/public_html ] && SETUP_PUBLIC_HTML=1
fi    


######################################################################
#
#                           MAIN TASKS
#
######################################################################

########################### JUST VERIFY ##############################
if [ "${JUST_VERIFY}" = "yes" ]; then
    USER_VOL=users.${USERNAME}
    U_VOL_USED=$(vos exa ${USER_VOL} -format 2>&1| awk '/diskused/ {print $2}')
    ((U_VOL_USED/=1024))
    U_VOL_QUOTA=$(vos exa ${USER_VOL} -format 2>&1| awk '/maxquota/ {print $2}')
    ((U_VOL_QUOTA/=1024))
    [ ${U_VOL_QUOTA} -eq 0 ] && U_VOL_PERCENT=0 || U_VOL_PERCENT=$((${U_VOL_USED}*100/${U_VOL_QUOTA}))
    P_VOL_USED=$(vos exa ${USER_VOL}.pub -format 2>&1| awk '/diskused/ {print $2}')
    ((P_VOL_USED/=1024))
    P_VOL_QUOTA=$(vos exa ${USER_VOL}.pub -format 2>&1| awk '/maxquota/ {print $2}')
    ((P_VOL_QUOTA/=1024))
    [ ${P_VOL_QUOTA} -eq 0 ] && P_VOL_PERCENT=0 || P_VOL_PERCENT=$((${P_VOL_USED}*100/${P_VOL_QUOTA}))
    cat<<ENDVERIFY
***** Verify for user ${USERNAME} ******
Home Directory volume: $(vos exa ${USER_VOL} 2>&1|head -n1 | sed 's/[0-9].*$//g')
    $(fs lsm /afs/ss2k/users/${INITIAL}/${USERNAME} )
  Usage:
    ${U_VOL_USED}/${U_VOL_QUOTA}MB - ${U_VOL_PERCENT}%

public_html volume: $(vos exa ${USER_VOL}.pub 2>&1|head -n1 | sed 's/[0-9].*//g')
   $(fs lsm /afs/ss2k/users/${INITIAL}/${USERNAME}/public_html )
  Usage:
    ${P_VOL_USED}/${P_VOL_QUOTA}MB - ${P_VOL_PERCENT}%

$(pts mem ${USERNAME})

$(verify-ad-attributes)
ENDVERIFY

    exit 0
fi

########################### USER CREATION ############################
run pts createuser ${USERNAME} -id ${USER_ID}

######################### ADD USER TO GROUPS #########################
while [ $((--GRP_I)) -ge 0 ]; do
    pts-add-user-to-group ${USERNAME} ${ADD_GROUPS[$GRP_I]}
done

########################### VOLUME CREATION ##########################
run vos create ${HOME_FS} ${HOME_PART} users.${USERNAME} -maxquota ${SET_QUOTA}
if [ $? -eq 0 ]; then
    RELEASE_NEW=yes
    run vos addsite ${HOME_FS} ${HOME_PART} users.${USERNAME}
    run vos addsite ${BACKUP_FS} ${BACKUP_PART} users.${USERNAME}
fi

run fs mkm ${HOME_DIR_RW} users.${USERNAME} -rw
[ $? -eq 0 ] && RELEASE_NEW=yes
run fs sa ${HOME_DIR_RW} ${USERNAME} write

[ ${SET_QUOTA} -ge 0 ] && run fs sq ${HOME_DIR_RW} ${SET_QUOTA}

[ ${RELEASE_NEW} = "yes" ] && run vos release users

########################### SETUP PUBLIC_HTML ########################
if [ ${SETUP_PUBLIC_HTML} -eq 1 ]; then
    [ ${DEBUG} -gt 0 ] && DO_DEBUG_REPLACE=-D
    [ -d ${HOME_DIR_RW}/public_html ] && DO_REPLACE_PUB=--replace-dir
    [ ${DEBUG} -gt 0 ] && cat<<afsmkandmountvolsh
DEBUG now calling: afs-mk-and-mount-vol.sh -v users.${USERNAME}.pub -m ${HOME_DIR_RW}/public_html \\
DEBUG:             -s ${HOME_FS} -rw ${USERNAME} -rw websscs -ro ${APACHE_USER} -ro ${WEBSERVER_MACHINES} \\
DEBUG:             -q $([ ${PUB_QUOTA} -ge 0 ] && echo -n ${PUB_QUOTA} || echo -n 1) \\
DEBUG:             ${DO_REPLACE_PUB} ${DO_DEBUG_REPLACE} ;
afsmkandmountvolsh
    afs-mk-and-mount-vol.sh -v users.${USERNAME}.pub -m ${HOME_DIR_RW}/public_html \
                -s ${HOME_FS} -rw ${USERNAME} -rw websscs -ro ${APACHE_USER} -ro ${WEBSERVER_MACHINES} \
                -q $([ ${PUB_QUOTA} -ge 0 ] && echo -n ${PUB_QUOTA} || echo -n 1) \
                ${DO_REPLACE_PUB} ${DO_DEBUG_REPLACE}
    [ ${DEBUG} -gt 0 ] && echo "DEBUG: end afs-mk-and-mount-vol.sh"
    run fs sa ${HOME_DIR_RW} ${APACHE_USER} l
    run fs sa ${HOME_DIR_RW} ${WEBSERVER_MACHINES} l
    run fs sa ${HOME_DIR_RW} websscs l

    if [ ${RESET_PERMS} = "yes" ]; then
        run fs sa ${HOME_DIR_RW} ${APACHE_USER} l
        run fs sa ${HOME_DIR_RW} ${WEBSERVER_MACHINES} l
        run fs sa ${HOME_DIR_RW} websscs l
        run find ${HOME_DIR_RW}/public_html -type d -exec fs sa -clear -dir {} \
                                        -acl system:administrators all \
                                        -acl ${APACHE_USER} rl \
                                        -acl ${WEBSERVER_MACHINES} rl \
                                        -acl websscs write \
                                        -acl ${USERNAME} write \; 
    fi
    RELEASE_NEW=yes
fi

################## IF NEEDED, DO TRANSFER FROM NAS ###################
if [ "${DO_TRANSFER}" = "yes" ]; then
    if [ -r /u/nas/${USERNAME} ]; then
        run rsync -rlt /u/nas/${USERNAME}/ ${HOME_DIR_RW}/
        if [ $VERBOSITY -gt 2 ]; then
            run chmod -v -R u+rwx ${HOME_DIR_RW}
            run chown -v -R ${USERNAME} ${HOME_DIR_RW}
        else
            run chmod -R u+rwx ${HOME_DIR_RW} 2>/dev/null
            run chown -R ${USERNAME} ${HOME_DIR_RW} 2>/dev/null
        fi
        RELEASE_NEW=yes
    else
        echo "No home directory exists to transfer"
    fi
fi

######################## RESET PERMISSIONS ###########################
if [ ${RESET_PERMS} = "yes" ]; then
    run find ${HOME_DIR_RW} -type d -exec fs sa {} ${USERNAME} write \;
    if [ -d ${HOME_DIR_RW}/private ]; then
        run find ${HOME_DIR_RW}/private -type d \
        -exec fs sa {} system:administrators all ${USERNAME} write -clear \;
    fi
    if [ $VERBOSITY -gt 2 ]; then
        run chmod -v -R u+rwx ${HOME_DIR_RW}
        run chown -v -R ${USERNAME} ${HOME_DIR_RW}
    else
        run chmod -R u+rwx ${HOME_DIR_RW} 2>/dev/null
        run chown -R ${USERNAME} ${HOME_DIR_RW} 2>/dev/null
    fi
    RELEASE_NEW=yes
fi

####################### RELEASE OF USER VOLUME #######################
[ ${RELEASE_NEW} = "yes" ] && run vos release users.${USERNAME}


################ Check if profile in AD points to AFS ###############
#function verify-ad-attirbutes defined in afs-helper-functions.sh
verify-ad-attributes
