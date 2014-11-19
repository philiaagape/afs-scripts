#!/bin/bash

AFS_MONITOR_DIR=/usr/local/afs-monitor

DB_SERVER_PATTERN="afsdb[0-9]*"
MY_FS_SERVERS=$(vos listaddrs | cut -d. -f1 | sort | grep -v "${DB_SERVER_PATTERN}")
MY_DB_SERVERS=$(vos listaddrs | cut -d. -f1 | sort | grep "${DB_SERVER_PATTERN}")

if [ -d ${AFS_MONITOR_DIR} ]; then
    cd ${AFS_MONITOR_DIR}
else
    cat<<REQUIS
This script depends on the following afs-monitor nagios scripts: 
 * check_afs_bos
 * check_afs_udebug
 * check_afs_rxdebug

I install them to ${AFS_MONITOR_DIR}.
Install these scripts somewhere with these commands:

cd ${AFS_MONITOR_DIR%%/afs-monitor}
git clone git://git.eyrie.org/afs/afs-monitor.git

If you do not install them to ${AFS_MONITOR_DIR} then modify this script.
Change the variable at the top to point to the correct directory.
REQUIS
    exit 1
fi

echo "Checking DB servers:"
for db_srv in ${MY_DB_SERVERS}; do
    echo -n "${db_srv}: "; ./check_afs_bos -H ${db_srv}
    for srv_port in 7002 7003; do
        echo -n "${db_srv}:${srv_port}: "; ./check_afs_udebug -H ${db_srv} -p ${srv_port}
    done
done

echo "Checking FS servers:"
for fs_srv in ${MY_FS_SERVERS}; do
    echo -n "${fs_srv}: "; ./check_afs_bos -H ${fs_srv}
    echo -n "${fs_srv}: "; ./check_afs_rxdebug -H ${fs_srv}
done

