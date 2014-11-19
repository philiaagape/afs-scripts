#!/bin/bash
#
# Title: afs-list-mountpoints.sh
#
# Author: Jonathan Nilsson, jnilsson@uci.edu
#
# Version: 0.4.6
#

CACHE_DIR=/afs/ss2k/system/mountpoint_cache
declare -a CACHE_BASE_PATHS
CACHE_BASE_PATHS=(
            "/afs/ss2k/users" \
            "/afs/ss2k/departments" \
            "/afs/ss2k/centers" \
            "/afs/ss2k/web" \
            "/afs/ss2k/shares" \
            "/afs/ss2k/shares/BusinessShare" \
            "/afs/ss2k/system" );

#based this off of 'afs-get-user-distribution -g 65'
BASE_USERS_RANGE=(
            "a-b" \
            "c" \
            "d-e" \
            "f-i" \
            "j" \
            "k-l" \
            "m" \
            "n-r" \
            "s-t" \
            "u-z");
#NOTE: the output filenames of the cache files will be like:
# ${last_path_element}[_${range}].txt => users_a-b.txt

#'old' cache threshold in weeks. default is 2. i may add option for this...
CACHE_AGE_THRESHOLD=2

function usage() {
cat<<HELP_1
Usage: `basename $0` [-u] [<pattern>]

Options:
    -u     Optionally, update the mountpoint cache before searching.
           I will prompt you for one of the following values:
HELP_1
bi=0
while [ $bi -lt ${#CACHE_BASE_PATHS[@]} ]; do
echo -e "            $((bi+1))) ${CACHE_BASE_PATHS[$((bi++))]}"
done
cat<<HELP_2

    <pattern>   A search pattern; can be part of a path or volume name.
                This can be an extended regular expression, as it is passed
                to "grep -E". See Examples below for more info.

Output:
        Each line of output represents one match of the form:

    "/afs/ss2k/path/to/mount/point" [#%]volume.name
        
        The "#" or "%" volume name prefixes indicate RO and RW mount
        point types, respectively.

Examples:
        Here are some sample patterns you can use to get more specific results,
        such as matching only the volume name or only a directory name:
        
        1. match a volume name (start the pattern with # or %):
            "[#%].*econ.*"     => find RO or RW mount points for the econ dept
            "#.*acct$"         => find RO mountpoints for ".acct" volumes

        2. find mount points burried at least N directory levels deep:
            "/([^/]*/){N,}"    => remove the comma to find an exact match 'n'
                                  levels deep.
        
        3. find mounted backup volumes:
            "#.*\.backup"      => the automatic AFS .backup volume
            "#.*.[0-9]*$"      => temp restored volumes, to which i usually
                                  add a numeric date suffix. these should be
                                  'fs rmm'-ed and 'vos remove'-ed when the
                                  restore is complete.

Version: $(awk '/^# Version:/ {print $3}' $0)

HELP_2
exit 1
}

#function do_update_cache( afs_path, output_file )
#  call this function from prompt_update_cache or when a cache file is old
#  use 'find' to run 'fs lsm' on some afs_path
#   - handle special case for users/user_range/ (limit searching)
#  save output where "is a mount point" is returned
#   - save the mountpoint path and volume name
function do_update_cache() {
    afs_path=$1
    #strip the .txt so i can get at the optional _range added to the end
    output_file=${2%.txt}
    #test if there is a _a-z or _a type of range suffix
    # if so, then strip the prefix up to the last underscore to get the users_range
    users_range=
    echo "${output_file}" | grep -qE "_[a-z](-[a-z])?$" && users_range=${output_file##*_}

    #save output to a tmp file first, then move to output_file
    tmp_file="/tmp/cache_update_${output_file}_$$"

    # special case, if this is an update on the users/[users_range]/ path
    if [ -n "${users_range}" ]; then

        echo "Updating cache for base path: ${afs_path}/[${users_range}]:"
        #split the processing of users into 3 disjoint sets of paths:
        # 1) /afs/ss2k/users/?/<username>/shares/<mount_point>/<mount_point>
        # 2) /afs/ss2k/users/?/<username>/personal/<mount_point>
        # 3) /afs/ss2k/users/?/<username>/<anything_else>
        find ${afs_path}/[${users_range}] \
            -noleaf \
            -maxdepth 4 \ -type d \
            -path "*/shares*" \
            -exec fs lsm "{}" \; 2>&1 | \
            grep "is a mount point" | awk -F\' '{print "\"" $2 "\" " $4}' \
            > ${tmp_file}
        find ${afs_path}/[${users_range}] \
            -noleaf \
            -maxdepth 3 \
            -type d \
            -path "*/personal*" \
            -exec fs lsm "{}" \; 2>&1 | \
            grep "is a mount point" | awk -F\' '{print "\"" $2 "\" " $4}' \
            >> ${tmp_file} 
        find ${afs_path}/[${users_range}] \
            -noleaf \
            -maxdepth 2 \
            -type d \
            -path "*/personal" -prune -o \
            -path "*/shares" -prune -o \
            -exec fs lsm "{}" \; 2>&1 | \
            grep "is a mount point" | awk -F\' '{print "\"" $2 "\" " $4}' \
            >> ${tmp_file} 
    else # it is an update for the complete afs tree starting at afs_path
        echo "Updating cache for base path: ${afs_path}"
        find "${afs_path}" \
            -noleaf \
            -type d \
            -exec fs lsm "{}" \; 2>&1 | \
            grep "is a mount point" | awk -F\' '{print "\"" $2 "\" " $4}' \
            > ${tmp_file}
    fi

    mv ${tmp_file} ${CACHE_DIR}/${output_file}.txt
    if [ $? -ne 0 ]; then
        echo "Error moving the temporary cache file '${tmp_file}' to"
        echo "the cache location '${CACHE_DIR}'."
    fi 
    echo "Done updating cache file: ${CACHE_DIR}/${output_file}.txt"
}

#function prompt_update_cache
# prompt for a path from CACHE_BASE_PATHS (defined as a global variable above)
# if needed, prompt for a narrower range of users from BASE_USERS_RANGE
# call the 'do_update_cache' function to do the update
function prompt_update_cache() {

    #Test that we have write access to the cache
    touch ${CACHE_DIR}/.test 2>/dev/null && \
    echo "test" > ${CACHE_DIR}/.test && \
    /bin/rm -f ${CACHE_DIR}/.test

    if [ $? -ne 0 ]; then
        echo "Skipping Update: You don't have write access to '$CACHE_DIR}'"
    else
        base_path=
        #we do have write access to the cache, so do the update
        #prompt for the base path to update
        echo "Please select from the following base paths:"
        while [ -z "${base_path}" ]; do
            select base_path in "${CACHE_BASE_PATHS[@]}"; do break; done
            [ -z "${base_path}" ] && \
            echo "Error: Unrecognized selection '${REPLY}'. " && \
            echo "Try again, or Ctrl-C to quit."
        done
        
        cache_file="$(echo ${base_path} | awk -F/ '{print $NF}').txt"

        # if 'users' was selected, we have to get a narrower range
        if [ "${base_path}" = "/afs/ss2k/users" ]; then
            users_range=
            cat<<ENDUSERWARN
Warning: In practice, I have found that it is too much to do a complete search
of the 'users' directory tree. I only search for these expected mount point
locations:
 * users/<initial>/<username>/shares/<mount_points>/<mount_points>
 * users/<initial>/<username>/personal/<mount_points>
 * users/<initial>/<username>/<mount_points>
I have broken down the list of users into reasonably-sized groups (60-90 users
per group). Please select a range of usernames to search for mountpoints:
ENDUSERWARN
            while [ -z "${users_range}" ]; do
                select users_range in "${BASE_USERS_RANGE[@]}"; do break; done
                [ -z "${users_range}" ] && \
                echo "Error: Unrecognized selection '${REPLY}'. " && \
                echo "Try again, or Ctrl-C to quit."
            done

            cache_file=${cache_file/%.txt/_${users_range}.txt}
        fi

        do_update_cache ${base_path} ${cache_file}
    fi #close, test write access to cache
}

#function update_old_cache_file( filename )
# - at the point when this function is called, all i know is the
#   filename of the old cachefile.
# - need to determine which CACHE_BASE_PATHS matches the given filename
# - call do_update_cache on that base_path
function update_old_cache_file() {
    #strip the '.txt' suffix and the '_<range>' suffix
    filename=${1%.txt}
    stripped_filename=${filename%_*}

    #search through the CACHE_BASE_PATHS array for the matching base_path
    found=0
    base_path=
    for base_path in ${CACHE_BASE_PATHS[@]}; do
        [ "${stripped_filename}" = "${base_path##*/}" ] && { found=1; break; }
    done
    
    #if a matching base_path was found, do the update
    #else, probably there is a .txt file in the cache directory that is
    # not named properly, i.e. it was not added by this script so i can't
    # update it.
    [ ${found} -eq 1 ] && do_update_cache "${base_path}" "${filename}.txt" || \
    echo "Error: cache file '${filename}.txt' does not match a known afs path."
}

##############################################################################
# read args, call prompt_update_cache if needed, or display usage
##############################################################################
[ $# -eq 0 ] && usage

DO_UPDATE=0
while [ $# -gt 0 ]; do
    case $1 in
        -u) DO_UPDATE=1; prompt_update_cache; ;;
        -h|--help) usage; ;;
        -*) echo "ERROR: Unknown argument '$1'."; usage; ;;
        *) PATTERN=$1; ;;
    esac
    shift
done

##############################################################################
#  MAIN
##############################################################################

#if no PATTERN, then they just wanted to update the cache
[ -z "${PATTERN}" ] && exit

#make sure the cache files exist
[ -r ${CACHE_DIR} ] || { echo "ERROR: no read access to '${CACHE_DIR}'"; exit 1; }

# if we didn't just update a cache file, then check the age of the cache
if [ ${DO_UPDATE} -eq 0 ]; then
    cur_sec=$(date "+%s")
    #the number of seconds defined as the "old" threshold
    threshold=$((60*60*24*7*${CACHE_AGE_THRESHOLD}))
    #check each cache file to see if it is old
    for cfile in $(/bin/ls -1 ${CACHE_DIR}); do
        cfile_sec=$(/bin/ls -l --time-style="+%s" ${CACHE_DIR}/$cfile | awk '{print $6}'|sed 's/^0//')
        # compare the current time to the file's timestamp and warn if it is older than threshold
        if [ $((${cur_sec}-${cfile_sec})) -gt ${threshold} ]; then
            echo "Warning: '${cfile}' is older than ${CACHE_AGE_THRESHOLD} weeks."
            read -p "Do you want to update it? [y|N]" my_do_update
            [ "${my_do_update}" = "y" -o "${my_do_update}" = "Y" ] && \
             update_old_cache_file ${cfile}
        fi
    done
fi

#do the search
#remove the leading path to the cache file
#sort uniquely to remove duplicates
grep -E "${PATTERN}" ${CACHE_DIR}/*.txt | sed 's/^.*:"/"/' | sort -u

#maybe filter the search to output more helpful info...
# 1) if pattern is a directory (contains a slash)...
# 2) if pattern is a volume (begins with # or %)...
# 3) summary info? how many matches? how many duplicate mount points for same volume?
