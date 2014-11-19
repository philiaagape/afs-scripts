#!/bin/bash

fs lq . 2>&1 | grep -q "is not in AFS"
RETVAL=$?
if [ $RETVAL -eq 1 ]; then
	while [ "`pwd`" != "/" ]; do
	THIS_DIR=$(pwd | awk -F/ '{print $NF}')
	THIS_VOL=$(fs lsm ../${THIS_DIR} 2>&1 | grep "is a mount point" | awk -F\' '{print $4}')
	[ "x${THIS_VOL}" != "x" ] && { pwd; break 2; }
	cd ../
	done
else
	echo "Current directory is not in AFS"
fi
