#!/bin/sh
#
# Greenboot script for the server-side component.
# This script contains the coordination logic needed to implement the downstream client updates
#

(
    for i in 1 2 3; do
        UPGRADE_AVAILABLE=$(fw_printenv upgrade_available | cut -d '=' -f 2)
        [ -n "${UPGRADE_AVAILABLE}" ] && break
        echo "Error reading upgrade_available from U-Boot environment.  Waiting 1s and trying again"
        sleep 1
    done
    
    UPGRADE_AVAILABLE=$(fw_printenv upgrade_available | cut -d '=' -f 2)
    if [ ${UPGRADE_AVAILABLE} = "1" ]; then
        # Handle coordination between gateway and client devices
        # here for synchronous update and rollback
        echo "We are in an upgrade."

        if [ -e /nfs/update_secondary.tar ]; then
            # Extract the secondary update and create a symlink to /nfs/update
            # This ensures that the artifact is completely extracted by the time
            # the client device detects it.
            echo "Extracting /nfs/update_secondary.tar"
            tar -C /nfs -xf /nfs/update_secondary.tar
            echo "Creating /nfs/update symlink"
            ln -sf /nfs/update_secondary /nfs/update
        fi

        # TODO: Wait for response from client and cleanup
    elif [ ${UPGRADE_AVAILABLE} = "0" ]; then
        # No upgrade in process
        echo "We are not in an upgrade."
    else
        echo "Unknown value of UPGRADE_AVAILABLE \"${UPGRADE_AVAILABLE}\""
    fi
) >>/tmp/nfs-server-coordination-log.txt

exit 0
