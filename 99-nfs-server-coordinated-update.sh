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

            # Wait for the client to update or rollback
            client_feedback_file=$(ls /nfs/ | grep "client")
            while [ -z "$client_feedback_file" ]; do
                client_feedback_file=$(ls /nfs/ | grep "client")
                echo Waiting for client to update or rollback
                sleep 5;
            done

            # update needs to be removed if client has updated successfully or rolled back
            echo Cleaning up update files
            rm -rf /nfs/update /nfs/update_secondary

            # If client has rolled back
            if [ -e /nfs/client.on.rollback ]; then
                echo "Cleaning up rollback feedback from client"
                echo "Rolling back server"
                fw_setenv rollback 1
            elif [ -e /nfs/client.update.done ]; then
                echo "Client has successfuly updated"
                rm -f /nfs/client.update.done
            else
                echo "Error. Unexpected client status: $(echo /nfs/client*)"
            fi
        fi
    elif [ ${UPGRADE_AVAILABLE} = "0" ]; then
        # No upgrade in process
        echo "We are not in an upgrade."
    else
        echo "Unknown value of UPGRADE_AVAILABLE \"${UPGRADE_AVAILABLE}\""
    fi
) >>/tmp/nfs-server-coordination-log.txt

rc=0
if [ -e /nfs/client.on.rollback ]; then
    rm -f /nfs/client.on.rollback
    rc=1
elif [ -e /nfs/client.update.done ]; then
    rm -f /nfs/client.update.done
fi
    
exit ${rc}
