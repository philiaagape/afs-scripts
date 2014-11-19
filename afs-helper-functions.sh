#!/bin/bash
##############################################################################
#
#                  DEFINE FUNCTIONS
#
# File Version: 2.2.2
#
# ############################################################################

# setup the defualt AFS quota list:
# 1GB for grads, 2GB for staff, 4GB for faculty
QUOTA_LIST=($((1024*1024)) $((1024*1024*2)) $((1024*1024*4)))


##############################################################################
# function run()
# - do some error checking to sanitize/validate input
# - verify if the command needs to be run (has it already been run?)
# - if the verbosity is high enough, output more info
# - if debugging is enabled, don't actually run the command
#
##############################################################################
function run() {
    # DO_IT values: 0 means don't do it, 1 means do it
    # Since I use the exit code of a command to set DO_IT,
    # sometimes you have to reverse the logic to get the value right
    DO_IT=1
    # build COMMAND below. sometimes "$*" is sufficient.
    # other times, quoting individual arguments is necessary.
    COMMAND="$*"
    # MESSAGE will be displayed if COMMAND is not run
    MESSAGE=

    # set default values for DEBUG and VERBOSITY to highest if not set
    # use a bash variable expansion trick ${name:=value}
    # to set to 'value' if 'name' is unset
    echo ${DEBUG:=9} >/dev/null
    echo ${VERBOSITY:=9} >/dev/null

#pts createuser
    if [ "$2" = "createuser" ]; then
        # don't do it if the user already exists
        pts examine "$3" &> /dev/null
        DO_IT=$?
        MESSAGE="Entry '$3' already exists"
        COMMAND="$*"
#vos create
    elif [ "$2" = "create" ]; then
        #check volume name length <= 22
        VOL=$5
        while [ ${#VOL} -gt 22 ]; do
            echo "Volume Name '${VOL}' is too long. Enter a value"
            echo "that is shorter than 22 characters:"
            prompt -p "> " VOL
        done
        #don't do it if the volume already exists
        vos examine ${VOL} &> /dev/null
        DO_IT=$?
        MESSAGE="Volume '${VOL}' already exists"
        SET_QUOTA=$7
        if [ ${DO_IT} -ne 0 -a ${SET_QUOTA:=-1} -lt 0 ]; then
            cat<<-ENDQUOTA
            What quota should be used? Is this user:
              1) a grad student ($((${QUOTA_LIST[0]} / 1024 / 1024)) GB )
              2) a staff ($((${QUOTA_LIST[1]} / 1024 / 1024)) GB)
              3) a faculty ($((${QUOTA_LIST[2]} / 1024 / 1024)) GB)
ENDQUOTA
            WHICH=0
            while [ $WHICH -ne 1 -a $WHICH -ne 2 -a $WHICH -ne 3 ]; do
                read -p "[1|2|3]? " WHICH
            done
            SET_QUOTA=${QUOTA_LIST[$((--WHICH))]}
        fi
        COMMAND="vos create $3 $4 ${VOL} -maxquota ${SET_QUOTA}"
#vos addsite
    elif [ "$2" = "ad" -o "$2" = "add" -o "$2" = "adds" -o "$2" = "addsite" ]; then
        # don't do it if the site is already added
        vos listvldb -name $5 2>&1| grep -q "$3.* partition .*$4 RO"
        DO_IT=$?
        MESSAGE="Volume $5.readonly already exists at site '$3 $4'"
        COMMAND="$*"
#fs remsite
    elif [ "$2" = "rems" -o "$2" = "remsite" ]; then
        # don't do it if there is no site to remove
        vos listvldb -name $5 2>&1| grep -q "$3.* partition .*$4 RO"
        [ $? -eq 0 ] && DO_IT=1 || DO_IT=0
        MESSAGE="Volume $5.readonly does not exist at site '$3 $4'"
        COMMAND="$*"
#echo
    elif [ "$1" = "echo" ]; then
                shift  
                MESSAGE="$*"
                DO_IT=0
#rsync
    elif [ "$1" = "rsync" ]; then
        shift
        COMMAND="rsync $*"
        [ ${VERBOSITY} -gt 1 ] && COMMAND="rsync -v $*"
    fi

    # normally we can just run the $COMMAND as it is set above.
    # but if one of the arguments must be quoted, we need to create
    # a special case here to handle it.
    #  * pts creategroup - 'group name' could have a space
    #  * pts adduser - 'group name' could have a space
    #  * fs mkm - 'mount point' could have a space
    #  * fs sq - 'directory name' could have a space

    #SPECIAL CASE: pts creategroup
    # handle the case where 'group name' has a space in it
    if [ "$2" = "creategroup" ]; then
        # don't do it if the group already exists
        pts examine "$3" &> /dev/null
        DO_IT=$?
        MESSAGE="Entry '$3' already exists"
        #handle the case where groupname has a space in it
        if [ ${DO_IT} -eq 0 ]; then
            #just echo the message if verbosity is high
            [ ${VERBOSITY} -gt 1 ] && echo "${MESSAGE}"
        else
            #echo debug prefix if debug mode is on
            [ ${DEBUG} -gt 0 ] && echo -n "DEBUG: "
            #echo the command if verbosity is on
            [ ${VERBOSITY} -gt 0 ] && echo "pts creategroup \"$3\""
            #run the command if debug is not set
            if [ ${DEBUG} -eq 0 ]; then
                pts creategroup "$3"
                return $?
            fi
        fi
        return 0
    #SPECIAL CASE: pts adduser
    # handle the case where 'group name' has a space in it
    elif [ "$2" = "adduser" ]; then
        # don't do it if the user is already a member
        pts mem $3 2>&1 | grep -qi $4
        DO_IT=$?
        MESSAGE="User '$3' is already a member of '$4'"
        #handle the case where 'group name' has a space in it
        if [ ${DO_IT} -eq 0 ]; then
            #just echo the message if verbosity is high
            [ ${VERBOSITY} -gt 1 ] && echo "${MESSAGE}"
        else
            #echo debug prefix if debug mode is on
            [ ${DEBUG} -gt 0 ] && echo -n "DEBUG: "
            #echo the command if verbosity is on
            [ ${VERBOSITY} -gt 0 ] && echo "pts adduser $3 \"$4\""
            #run the command if debug is not set
            if [ ${DEBUG} -eq 0 ]; then
                pts adduser $3 "$4"
                return $?
            fi
        fi
        return 0
    #SPECIAL CASE: fs mkmount
    # handle the special case where the mountpoint has a space
    elif [ "$2" = "mkm" -o "$2" = "mkmount" ]; then
        # don't do it if the mountpoint already exists
        fs lsm "$3" 2>&1 | grep -q "is a mount point"
        DO_IT=$?
        MESSAGE="Location '$3' is already a mount point"
        if [ ${DO_IT} -eq 0 ]; then
            #just echo the message if verbosity is high
            [ ${VERBOSITY} -gt 1 ] && echo "${MESSAGE}"
            #return 1 so we know the command didn't do anything
            return 1
        else
            #echo debug prefix if debug mode is on
            [ ${DEBUG} -gt 0 ] && echo -n "DEBUG: "
            #echo the command if verbosity is on
            [ ${VERBOSITY} -gt 0 ] && echo "fs mkm \"$3\" $4 $5"
            #run the command if debug is not set
            if [ ${DEBUG} -eq 0 ]; then
                fs mkm "$3" $4 $5
                return $?
            fi
        fi
        return 0
    #SPECIAL CASE: fs sq
    # handle the case where 'mount point' has a space in it
    elif [ "$2" = "sq" -o "$2" = "setquota" ]; then
        #echo debug prefix if debug mode is on
        [ ${DEBUG} -gt 0 ] && echo -n "DEBUG: "
        #echo the command if verbosity is on
        [ ${VERBOSITY} -gt 0 ] && echo "fs setquota \"$3\" $4 $5"
        #run the command if debug is not set
        if [ ${DEBUG} -eq 0 ]; then
            fs sq "$3" $4 $5
            return $?
        fi
        return 0
    fi

    # DEFAULT COMMAND PROCESSING
    #handle the rest of the cases with the default DEBUG and VERBOSITY handling
    if [ $DO_IT -eq 0 ]; then
        # don't do it, just echo the message if verbosity is high
        [ $VERBOSITY -gt 1 ] && echo "$MESSAGE"
        #return 1 so we know the command didn't do anything
        return 1
    else
        #echo debug prefix if debug mode is on
        [ ${DEBUG} -gt 0 ] && echo -n "DEBUG: "
        # echo the command if verbosity is on at all
        [ $VERBOSITY -gt 0 ] && echo $COMMAND
        # run the command if debug is not set
        if [ ${DEBUG} -eq 0 ]; then
            $COMMAND
            return $?
        else
            return 0
        fi
    fi
}


##############################################################################
#function afs-recursive-acl-on-dir(<dir> <ptsent> <perm>)
# * <dir> can have spaces!
# * <ptsent> is a user or group which should have already been created
# * <perm> is 'read', 'write', 'all' or 'none'
#
# - set ACL (<ptsent> <perm>) recusively on <dir>
##############################################################################
function afs-recursive-acl-on-dir() {
    
    #set the default DEBUG and VERBOSITY if unset
    echo ${DEBUG:=9} >/dev/null
    echo ${VERBOSITY:=9} >/dev/null

    # add a clear "DEBUG: " prefix when running in debug mode:
    [ ${DEBUG} -gt 0 ] && echo -n "DEBUG: "

    DIR="$1"
    ENTITY="$2"
    PERMISSION=$3
    [ ${VERBOSITY:=1} -gt 0 ] && \
    echo "find \"${DIR}\" -type d -exec fs sa {} \"${ENTITY}\" ${PERMISSION} \\;"
    [ ${DEBUG} -eq 0 ] && \
    find "${DIR}" -type d -exec fs sa {} "${ENTITY}" ${PERMISSION} \;
}
    

##############################################################################
#function afs-system-administrators-check
# - determine if the current user has tokens
# - and is a member of 'system:administrators'
##############################################################################
function afs-system-administrators-check() {
    MY_AFS_ID=$(tokens | awk -F[\ \)] '/^User/ {print $4}' )
    if [ -n "${MY_AFS_ID}" ]; then
        MY_AFS_NAME=$(pts exa ${MY_AFS_ID} | awk -F[\ ,] '/^Name/ {print $2}')
        pts mem ${MY_AFS_NAME} | grep -q "^\ *system:administrators"
        if [ $? -ne 0 ]; then
            echo "ERROR: You must be a member of system:administrators to run this script."
            exit 1
        fi
    else
        echo "ERROR: You do not have any AFS tokens."
        echo "Please run 'kinit <username>' and 'aklog' as a member of system:administrators."
        exit 1
    fi
}


##############################################################################
# function afs-verify-replace-dir( <mountpoint> <do_replace_dir> )
# - verify if <mountpoint> is a dir and if <do_replace_dir> is set to true
#
# this is a safety check to make sure the caller knows what they are asking.
# call this function before you call 'afs-replace-dir-with-vol'.
##############################################################################
function afs-verify-replace-dir() {
    DIR="$1"
    DO_REPLACE_DIR=$2
    # check if DIR is a mount point
    fs lsm "${DIR}" 2>&1 | grep -q "is a mount point"
    IS_MNT=$?
    # check if DIR is a directory
    fs lsm "${DIR}" 2>&1 | grep -q "is not a mount point" && [ -d ${DIR} ]
    IS_DIR=$?
    # ideal conditions:
    if [ "${DO_REPLACE_DIR}" = "true" -a ${IS_DIR} -eq 0 -a ${IS_MNT} -eq 1 ]; then
        run echo "INFO: successfully verified desired mount point as existing directory."
        run echo "I will copy the contents of '${DIR}' into the new volume."
    # if it is a directory, but --replace-dir not specified, then ERROR
    elif [ "${DO_REPLACE_DIR}" = "false" -a ${IS_DIR} -eq 0 ]; then
        echo "ERROR: '${DIR}' already exists and is a regular directory."
        echo "If you intend to replace this directory with a volume mount point,"
        echo "then pass the argument '--replace-dir' to this command."
        exit 1
    # if DIR is a mount point, then exit. we can't replace it.
    elif [ "${DO_REPLACE_DIR}" = "true" -a ${IS_MNT} -eq 0 ]; then
        echo "INFO: '${DIR}' is already a mount point! Can't replace it."
        exit 1
    # if neither, then dru/files/<CN> doesn't exist, so prompt for confirmation
    elif [ "${DO_REPLACE_DIR}" = "true" -a ${IS_DIR} -eq 1 ]; then
        echo "WARNING: '${DIR}' does not exist,"
        echo "but you used the option '--replace-dir'. Please confirm that"
        echo "you still want to create a volume named '${VOLUME_NAME}' and"
        echo "mount it at the location '${DIR}'"
        read -p "Confirm [y/N]? " CONFIRMED
        [ "$CONFIRMED" = "y" -o "$CONFIRMED" = "Y" ] || exit 0
	#avoid further error messages about missing directory by setting this false
	REPLACE_DIR=false
    fi
}


##############################################################################
# function afs-replace-dir-with-vol( <mountpoint> <volume> [y|n])
# - move <mountpoint> to <mountpoint>.old
# - mount the <volume> at <mountpoint>
# - copy contents of <mountpoint>.old to <mountpoint>
# - prompt to remove <mountpoint>.old
#
# the third argument to this function is optional.
# * if $3 is "y" then the removal is forced 
# * if $3 is "n" then removal is automatically skipped, leaving "<mount>.old"
##############################################################################
function afs-replace-dir-with-vol() {
    MOUNT=$1
    VOL=$2
    FORCE_REMOVE=$3
    TRANSF_RETVAL=0
    # the mv and rsync commands could have arguments with spaces... therefore
    # do NOT use the "run mv ..." command to execute it
    if [ ${DEBUG} -gt 0 -o ${VERBOSITY} -gt 0 ]; then
        [ ${DEBUG} -gt 0 ] && echo -n "DEBUG: "
        echo "mv \"${MOUNT}\" \"${MOUNT}.old\""
        [ ${DEBUG} -gt 0 ] && echo -n "DEBUG: "
        echo "fs mkm \"${MOUNT}\" ${VOL} -rw"
        [ ${DEBUG} -gt 0 ] && echo -n "DEBUG: "
        echo "rsync -a \"${MOUNT}.old/\" \"${MOUNT}/\""
    fi
    if [ ${DEBUG} -eq 0 ]; then 
        mv "${MOUNT}" "${MOUNT}.old" && \
        fs mkm "${MOUNT}" ${VOL} -rw && \
        rsync -a "${MOUNT}.old/" "${MOUNT}/"
        TRANSF_RETVAL=$?
    fi
    [ ${TRANSF_RETVAL} -ne 0 ] && { \
            echo "ERROR: encountered an error copying '${MOUNT}' to volume '${VOL}'"; \
            echo "Original directory should be at '${MOUNT}.old'"; exit 1; }
    # what to do with the "${MOUNT}.old" directory
    if [ "${FORCE_REMOVE}" = "y" ]; then
            [ ${DEBUG} -gt 0 ] && echo -n "DEBUG: "
            [ ${DEBUG} -gt 0 -o ${VERBOSITY} -gt 0 ] && \
                echo "/bin/rm -rf \"${MOUNT}.old\""
            [ ${DEBUG} -eq 0 ] && \
                /bin/rm -rf "${MOUNT}.old"
    elif [ "${FORCE_REMOVE}" != "n" ]; then
        read -p "Remove '${MOUNT}.old'? [y|N] " REM_OLD
        if [ "${REM_OLD}" = "y" -o "${REM_OLD}" = "Y" ]; then
            [ ${DEBUG} -gt 0 ] && echo -n "DEBUG: "
            [ ${DEBUG} -gt 0 -o ${VERBOSITY} -gt 0 ] && \
                echo "/bin/rm -rf \"${MOUNT}.old\""
            [ ${DEBUG} -eq 0 ] && \
                /bin/rm -rf "${MOUNT}.old"
        fi
    fi
}


##############################################################################
# function pts-add-user-to-group( <user> <group> )
# - add a user (passed as argument 1) to a group (argument 2)
# - create the group if necessary
##############################################################################
function pts-add-user-to-group() {
    THIS_USER=$1; shift;

    # using $* because groups could be multi-word. like "Domain Admins"
    THIS_GROUP="$*"

    pts exa "${THIS_GROUP}" &>/dev/null
    if [ $? -eq 0 ]; then
        run pts adduser ${THIS_USER} "${THIS_GROUP}"
    else
        CREATE_GROUP=n
        echo "The group '${THIS_GROUP}' is not in the PTS database."
        read -p "Create it? [y|N]: " CREATE_GROUP
        if [ $CREATE_GROUP = "y" ]; then
            run pts creategroup "${THIS_GROUP}"
            run pts adduser ${THIS_USER} "${THIS_GROUP}"
        fi
    fi
}

##############################################################################
# function verify-ad-attributes()
# - use ldapsearch, if available
# - check the homeDirectory and unixHomeDirectory attributes
# - print a message if attributes are not set to their correct AFS locations
##############################################################################
function verify-ad-attributes() {
    LDAPSEARCHBIN=`which ldapsearch 2>/dev/null`
    LDAPBASE="dc=ss2k,dc=uci,dc=edu"
    LDAPHOST=128.195.133.145

    if [ -x ${LDAPSEARCHBIN:=/usr/bin/ldapsearch} ]; then
        MSHOMEDIR=$(${LDAPSEARCHBIN} -x -D ssldap -w ldap4ss -b "${LDAPBASE}" -h ${LDAPHOST} "(uid=${USERNAME})" | grep homeDirectory | awk '{print $2}')
        UNIXHOMEDIR=$(${LDAPSEARCHBIN} -x -D ssldap -w ldap4ss -b "${LDAPBASE}" -h ${LDAPHOST} "(uid=${USERNAME})" | grep unixHomeDirectory | awk '{print $2}')
        echo $MSHOMEDIR | grep -q "^..nas"
        if [ $? -eq 0 ]; then
            echo "The Active Directory profile U: drive is ${MSHOMEDIR}." 
            echo 'Remember to change it to \\afs\ss2k\users\'${INITIAL}'\'${USERNAME}
        else
            run echo "The Active Directory Profile U: drive is:"
            run echo "${MSHOMEDIR}"
        fi

        echo $UNIXHOMEDIR | grep -q "\/nas\/"
        if [ $? -eq  0 ]; then
            echo "The Active Directory unix attributes home directory is ${UNIXHOMEDIR}."
            echo "Remember to change it to /u/afs/${INITIAL}/${USERNAME}"
        else
            run echo "The Active Directory unix attributes home directory is:"
            run echo "${UNIXHOMEDIR}"
        fi
    else
        echo "No 'ldapsearch' available to verify settings in Active Directory."
        echo "Please manually check and update these attributes:"
        echo "Unix Attributes home directory: /u/afs/${INITIAL}/${USERNAME}"
        echo 'Profile U drive: \\afs\ss2k\users\'${INITIAL}'\'${USERNAME}
    fi
}

################################################################################
# function afs-find-unreleased-vols
# - optional argument -server to limit search to named fileserver
# - search vldb for "Not released" and print name of volume if found
################################################################################

function afs-find-unreleased-vols() {
    server=
    if [ $# -gt 0 ]; then
        case $1 in
            -s|-server) server=$2; shift; ;;
            -h|--help) echo "Usage: $(basename $0) [[-s|-server] <servername>]"; return; ;;
            -*) echo "Unknown option \"$1\""; return; ;;
            *) server=$1; ;;
        esac
    fi
    vos listvldb $([ -n "$server" ] && echo "-server $server") 2>/dev/null | \
    while read line; do
        tmp=$(echo $line|grep -v "number of sites"|grep -v "RWrite: "|grep -v "server "|grep -v "Total"|awk '{print $1}');
        [ -n "$tmp" ] && VOL=$tmp
        echo $line | grep -q "Not released" && echo "$VOL"
    done
}

################################################################################
# function afs-find-lonely-vols
# - optional argument -server limits search to named fileserver
# a "lonely" volume is one that doesn't have a local "RO" clone
################################################################################

function afs-find-lonely-vols() {
    server=
    [ $# -gt 0 ] &&  case $1 in
        -s|-server) server=$1; shift; ;;
        -h|--help) echo "Usage: $(basename $0) [[-s|-server] <servername>]"; return; ;;
        -*) echo "Unknown option \"$1\""; return; ;;
        *) server=$1; ;;
    esac

    vos listvldb $([ -n "$server" ] && echo "-server $server") 2>/dev/null| \
    while read line; do
        tmp=$(echo $line|grep -v "number of sites"|grep -v "RWrite: "|grep -v "server "|grep -v "Total");
        [ -z "$tmp" ] || { [ "${RO_RW_match}" = "false" ] && echo $VOL; \
                        VOL=$tmp; RW_server=""; RO_RW_match="false"; };
        tmp=$(echo $line|grep "RW Site"|awk '{print $2}');
        [ -z $tmp ] || RW_server=$tmp;
        RO_server=$(echo $line|grep "RO Site"|awk '{print $2}');
        [ -n "${RW_server}" -a "${RO_server}" = "${RW_server}" ] && RO_RW_match="true";
    done
}
