#!/bin/bash

if [ ! -e server-ip.txt ]; then
    echo Please create server-ip.txt with the IP address or FQDN of the server board
    exit 1
fi

if [ ! -e credentials.zip ]; then
    echo Please download account credentials from \"https://app.torizon.io/#/account\" to \"$(pwd)/credentials.zip\"
    exit 1
fi

if [ ! -e tcb-env-setup.sh ]; then
    wget https://raw.githubusercontent.com/toradex/tcb-env-setup/master/tcb-env-setup.sh
fi
source ./tcb-env-setup.sh -a remote
shopt -s expand_aliases

if [ ! -e shared-data.tar.gz ]; then
    torizoncore-builder platform provisioning-data \
                        --credentials credentials.zip \
                        --shared-data shared-data.tar.gz \
                        --online-data DEFAULT | tail -1 > online-data.txt
fi

cp -f shared-data.tar.gz credentials.zip apalis_imx8_v1/
cp -f shared-data.tar.gz credentials.zip apalis_imx8_update/
cp -f shared-data.tar.gz credentials.zip colibri_imx7_v1/
cp -f shared-data.tar.gz credentials.zip colibri_imx7_update/

sed -e "s~@server-ip@~$(cat server-ip.txt)" exports.in > apalis_imx8_v1/changes/usr/etc/exports
sed -e "s~@server-ip@~$(cat server-ip.txt)" exports.in > apalis_imx8_update/changes/usr/etc/exports
