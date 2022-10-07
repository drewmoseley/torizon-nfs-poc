#!/bin/bash

set -x

# cd /nfs_mnt/myshareddir # mount autofs directory

# sleep 5

while ! systemctl status autofs.service | grep -m1 ": active (running)"; do sleep 1; done

mountpoint -q /nfs_mnt/myshareddir

if mountpoint -q /nfs_mnt/myshareddir; then echo "SUCCESS" > /nfs_mnt/myshareddir/secondary_update_status.txt; fi
