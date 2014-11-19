#!/bin/bash
#
# Version: 0.4

function usage() {
cat<<ENDUSAGE
Usage: $(basename $0) [-a|-g <num>|-h]

Options:
    -a          Simply count all the users for each letter of the alphabet
                and display the distribution.
    -g <num>    Determine adjacent letter groupings that produces
                groups with about <num> users. Useful for determining
                appropriate sized group of users to batch process all at once.
    -h|--help   display this help message

Example usage:
    The 'afs-list-mountpoints.sh' script updates the cached list of volume
        mount points for all users, but it is unmanagable to search through
        all users at once. Instead, you can use this program to create a
        list of letter ranges of about 65 users:

        $(basename $0) -g 65

    If you just want to see how many users there are in each letter directory,
        sorted from fewest users to most users:

        $(basename $0) -a | sort -n -k 2

ENDUSAGE
exit
}

function get_user_distribution() {
    for l in $(echo {a..z}); do
        echo -n "$l "
        /bin/ls -1 /afs/ss2k/users/$l/ | wc -l
    done 
}

function get_groups_of_size() {
    max=$1
    sum=0
    newline=1
    get_user_distribution | \
     while read line; do 
        l=${line/ */}
        n=${line/* /}
        [ $newline -eq 1 ] && { echo -n "$l-"; newline=0; }
        ((sum+=n))
        [ $sum -gt $max ] && { echo "$l $sum"; sum=0; newline=1; }
        [ "$l" = "z" -a $sum -ne 0 ] && echo "z $sum"
     done
}

[ $# -eq 0 ] && usage

case $1 in
    -a) get_user_distribution; ;;
    -g) if [ -z "$2" ] || echo $2| grep -q "[^0-9]"; then
            echo "Error: missing <num> argument."; usage
        fi
        get_groups_of_size $2
        ;;
    *) usage; ;;
esac

