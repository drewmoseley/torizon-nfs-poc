#!/bin/sh
#
# Greenboot script for the client-side component.
# This script contains the coordination logic needed to implement the downstream client updates
#

(
    for i in 1 2 3; do
        UPGRADE_AVAILABLE=$(fw_printenv upgrade_available | cut -d '=' -f 2)
        [ -n "${UPGRADE_AVAILABLE}" ] && break
        echo "Error reading upgrade_available from U-Boot environment.  Waiting 1s and trying again"
        sleep 1
    done
    
    if [ ${UPGRADE_AVAILABLE} = "1" ]; then
        # Handle coordination between gateway and client devices
        # here for synchronous update and rollback
        echo "We are in an upgrade."

        # Signal the server that we are done
        touch /nfs/client.update.done

        # Cleanup the client
        [ -L /tmp/update ] && echo Cleaning /tmp/update && rm /tmp/update
    elif [ ${UPGRADE_AVAILABLE} = "0" ]; then
        # No upgrade in process
        echo "We are not in an upgrade."
    else
        echo "Unknown value of UPGRADE_AVAILABLE \"${UPGRADE_AVAILABLE}\""
    fi

    # implementing the coordinated rollback
    for i in 1 2 3; do
        IS_ROLLBACK=$(fw_printenv rollback | cut -d '=' -f 2)
        [ -n "${IS_ROLLBACK}" ] && break
        echo "Error reading rollback from U-Boot environment.  Waiting 1s and trying again"
        sleep 1
    done

    if [ ${IS_ROLLBACK} = "1" ]; then
        # Handle coordination between gateway and client devices
        # here for synchronous update and rollback
        echo "We are in a rollback."

        # Signal the server that we are on rollback
        touch /nfs/client.on.rollback
    elif [ ${IS_ROLLBACK} = "0" ]; then
        # Not in a rollback process
        echo "We are not in a rollback."
    else
        echo "Unknown value of IS_ROLLBACK \"${IS_ROLLBACK}\""
    fi
) >>/tmp/nfs-client-coordination-log.txt

exit 0

