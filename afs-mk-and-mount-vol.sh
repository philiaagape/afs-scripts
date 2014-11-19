#!/bin/bash
# afs-mk-and-mount-vol.sh
#
# Description: Script will create a volume, setup replication, release the volume, mount it, set the ACL
#
# Author: Jonathan Nilsson
# Version: 1.1.8

function usage() {
    cat<<EOH
    Usage: $(basename $0) [OPTIONS] -v <volume> -q <quota in GB> -m <mount point name>
            [-rw <user/group to assign write access>]+ [-ro <user/group to assign read-only access]+

    Required Arguments:
        -v <volume>         name of the volume to create
        -m <mount point>    name of the mount point (directory) for the new volume
        -q <quota in GB>    quota to assign, in whole number gigabytes

    Options:
        -D                  turn on debug/dry-run mode
        --quiet             disable the default verbosity
        -R|--replace-dir    replace existing directory with volume mount point. copy contents into volume.
                            leave the original directory at <mountpoint>.old, prompt to remove it
        --remove-old [y|n]  specify default behavior for removal of <mountpoint>.old rather than prompting
                            ('y' = do remove it, 'n' = skip removal)
        -s <server>         create the volume on the AFS fileserver <server>
        -p <partition>      create the volume on the named AFS fileserver's <partition> (i.e. "a" or "vicepa")
        -rw <user|group>    grant the named entity read/write access to the new volume.
        -ro <user|group>    grant the named entity read-only access to the volume.
                            both -ro and -rw will create a group if the name does not exist already

    Example:
    $(basename $0) -v users.jnilsson.pub -q 1 -m /u/afs/j/jnilsson/public_html \\
                    --replace-dir -rw jnilsson -rw websscs -ro apache-services
        * Setup the volume 'users.jnilsson.pub' with 1GB quota
        * Mount it at /u/afs/j/jnilsson/public_html
        * Transfer data from an existing publi_html directory, if one exists
        * Grant read/write access to the entity 'jnilsson' and 'websscs'
        * Grant read-only access to 'wservice'
        * If the -rw or -ro entity is not found, create a group with that name

    Author:`awk -F: '/^# Author:/ {print $2}' $0`

    Version:`awk -F: '/^# Version:/ {print $2}' $0`
EOH
    exit 1
}

[ $# -lt 6 ] && usage

# depend on these helper functions:
# - afs-system-administrators-check
# - afs-verify-replace-dir <dir> <do-it?true:false>
# - afs-replace-dir-with-vol <dir> <volume>
# - run <command>
HELPER_FUNCTIONS=/afs/ss2k/system/scripts/afs/afs-helper-functions.sh
#HELPER_FUNCTIONS=/afs/ss2k/users/j/jnilsson/myrepo/afs/afs-helper-functions.sh
[ -r ${HELPER_FUNCTIONS} ] && source ${HELPER_FUNCTIONS} || { echo "ERROR: couldn't read '${HELPER_FUNCTIONS}'"; exit 1; }

afs-system-administrators-check

##################################################################################
#    Read Arguments
##################################################################################

DEBUG=0
VERBOSITY=1
BACKUP_FS=afsro1
BACKUP_PART=a
SERVER_NAME=casablanca
PARTITION_NAME=a
RW_ENT_COUNT=0
declare -a RW_ENT_NAME
RO_ENT_COUNT=0
declare -a RO_ENT_NAME
REPLACE_DIR="false"
# if this is set to 'y' then auto-remove <mountpoint>.old
# if this is set to 'n' then don't remove <mountpoint>.old
# if this is set to '-1' then prompt for removal
REMOVE_OLD=-1

while [ $# -gt 0 ]; do
    case $1 in
        -D) ((DEBUG++)); ;;
        --quiet) VERBOSITY=0; ;;
        -v) VOLUME_NAME=$2; shift; ;;
        -q) QUOTA=$2; shift; ;;
        -m) MOUNT_POINT=$2; shift; ;;
        -rw) RW_ENT_NAME[((RW_ENT_COUNT++))]=$2; shift; ;;
        -ro) RO_ENT_NAME[((RO_ENT_COUNT++))]=$2; shift; ;;
        -s) SERVER_NAME=$2; shift; ;;
        -p) PARTITION_NAME=$2; shift; ;;
        -R|--replace-dir) REPLACE_DIR="true"; ;;
        --remove-old)
            if [ "$2" = "y" -o "$2" = "n" ]; then
                REMOVE_OLD=$2
            else
                echo "ERROR: --remove-old requires 'y' or 'n'"; exit 1;
            fi
            shift; ;;
        *) echo "ERROR: unkown option $1"; usage; ;;
    esac
    shift
done

if [ ${DEBUG} -gt 1 ]; then
    cat<<-ENDDEBUG
    VOLUME_NAME=${VOLUME_NAME}
    QUOTA=${QUOTA}
    MOUNT_POINT=${MOUNT_POINT}
    $(i=0; while [ $i -lt ${RW_ENT_COUNT} ]; do echo "RW_ENT_NAME=${RW_ENT_NAME[((i++))]}"; done)
    $(i=0; while [ $i -lt ${RO_ENT_COUNT} ]; do echo "RO_ENT_NAME=${RO_ENT_NAME[((i++))]}"; done)
    SERVER_NAME=${SERVER_NAME}
    PARTITION_NAME=${PARTITION_NAME}
    REPLACE_DIR=${REPLACE_DIR}
    REMOVE_OLD=${REMOVE_OLD}
ENDDEBUG
    exit 1
fi
[ -n "${VOLUME_NAME}" -a -n "${QUOTA}" -a -n "${MOUNT_POINT}" ] || \
{ echo "ERROR: missing a required argument."; usage; }

#############################################################################################
# Create the volume and mount point, replace an exising directory, set ACL for named groups
#############################################################################################

# check if mount point exists or is a directory, and REPLACE_DIR is false
# exit if failure
afs-verify-replace-dir "${MOUNT_POINT}" ${REPLACE_DIR}

# create the desired volume and setup replication to BACKUP_FS
run vos create ${SERVER_NAME} ${PARTITION_NAME} ${VOLUME_NAME} -maxquota $((1024*1024*${QUOTA}))
run vos addsite ${SERVER_NAME} ${PARTITION_NAME} ${VOLUME_NAME}
run vos addsite ${BACKUP_FS} ${BACKUP_PART} ${VOLUME_NAME}
run vos release ${VOLUME_NAME}

# if the directory exists, then replace it with the volume mount point
# else just mount the volume
if [ "${REPLACE_DIR}" = "true" ]; then
    # first, create a backup of the current volume, just in case
    run vos backup $(fs lq "${MOUNT_POINT}"/.. | grep -v '^Volume Name' | awk '/^[a-z]/ {print $1}')
    # this script takes care of copying the data and removing the old directory
    afs-replace-dir-with-vol "${MOUNT_POINT}" ${VOLUME_NAME} ${REMOVE_OLD}
else
    run fs mkm "${MOUNT_POINT}" ${VOLUME_NAME} -rw
fi

# set the quota (in case the script is re-run on an existing volume)
run fs sq "${MOUNT_POINT}" -max $((1024*1024*${QUOTA}))

# setup ACLs: create entries if needed and setup the write/read-only permissions
i=0; while [ $i -lt ${RW_ENT_COUNT} ]; do
    #if ${RW_ENT_NAME[$i]} is a username, don't run pts creategroup
    id ${RW_ENT_NAME[$i]} >/dev/null 2>&1 || run pts creategroup "${RW_ENT_NAME[$i]}"
    afs-recursive-acl-on-dir "${MOUNT_POINT}" "${RW_ENT_NAME[((i++))]}" write
done
i=0; while [ $i -lt ${RO_ENT_COUNT} ]; do
    #if ${RO_ENT_NAME[$i]} is a username, don't run pts creategroup
    id ${RO_ENT_NAME[$i]} >/dev/null 2>&1 || run pts creategroup "${RO_ENT_NAME[$i]}"
    afs-recursive-acl-on-dir "${MOUNT_POINT}" "${RO_ENT_NAME[((i++))]}" read
done
