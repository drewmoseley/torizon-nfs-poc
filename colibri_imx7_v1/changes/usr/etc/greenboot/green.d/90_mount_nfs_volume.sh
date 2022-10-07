#!/bin/bash

set -x

while ! systemctl status autofs.service | grep -m1 ": active (running)"; do sleep 1; done

mountpoint -q /nfs_mnt/myshareddir
