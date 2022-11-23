#!/bin/sh
#
# Force a reattempt connect to the /nfs automount and then
# check if the update is available. If so create a symlink
# to it in /tmp so that it is available to our aktualizr
# instance.
#

# See if we get a Stale file handle and restart the NFS
# mount if so
if ls /nfs 2>&1 | grep -q 'Stale file handle'; then
    echo Restarting NFS mount >&2
    systemctl restart nfs.mount
fi

# Testing if this exists will trigger the NFS mount to be
# refreshed. Unfortunately doing it in the systemd service
# script as a ConditionPathExists does not work.
if [ -e /nfs/update ] ; then
    echo Update artifact exists on server. Linking into /tmp >&2
    ln -s /nfs/update /tmp/update
else
    echo No update artifact exists on server. >&2
fi
