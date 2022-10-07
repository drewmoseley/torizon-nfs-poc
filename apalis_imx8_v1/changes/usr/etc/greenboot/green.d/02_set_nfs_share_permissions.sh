#!/bin/bash

set -x

sudo chown nobody:nogroup /nfs_mnt/myshareddir #no-one is owner

sudo chmod 777 /nfs_mnt/myshareddir #everyone can modify files

exportfs -a  #making the file share available

systemctl restart nfs-server.service
