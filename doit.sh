#!/bin/bash

for app in wget curl jq; do
    if [ -z "$(type -path $app)" ]; then
        echo Please install $app
        set +x
        exit 1
    fi
done

if [ ! -e server-ip.txt ]; then
    echo Please create server-ip.txt with the IP address or FQDN of the server board
    exit 1
fi

if [ ! -e api-credentials.txt ]; then
    echo Please create api-credentials.txt from the API Client manager here: https://app.torizon.io/#/account
    echo Access type needs to be api-minimal
    echo Line 1 is the Client ID
    echo Line 2 is the Client Secret
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

sed -e "s~@server-ip@~$(cat server-ip.txt)~" exports.in > apalis_imx8_v1/changes/usr/etc/exports
sed -e "s~@server-ip@~$(cat server-ip.txt)~" exports.in > apalis_imx8_update/changes/usr/etc/exports

for MACHINE_CONFIG in apalis_imx8_v1 colibri_imx7_v1; do
    (
        cd $MACHINE_CONFIG
        rm -rf tezi
        torizoncore-builder build
    )
done

API_CLIENT_ID=$(head -1 api-credentials.txt)
API_CLIENT_SECRET=$(tail -1 api-credentials.txt)
TDX_TOKEN=$(curl -s https://kc.torizon.io/auth/realms/ota-users/protocol/openid-connect/token \
				 -d client_id=${API_CLIENT_ID} -d client_secret=${API_CLIENT_SECRET} \
				 -d grant_type=client_credentials | jq -r .access_token)

# Make sure colibri_imx7_update is first in the list so that it
# can be built and included in the build of apalis_imx8_update
for MACHINE_CONFIG in colibri_imx7_update apalis_imx8_update; do
    (
        cd $MACHINE_CONFIG
        rm -rf tezi

        if [ -e "build.hash" ]; then
            echo Deleting image ${MACHINE_CONFIG}-$(cat build.hash)
            curl -s --header "Authorization: Bearer ${TDX_TOKEN}" \
			     --header "Content-Type: application/json" \
			     --location \
			     --request DELETE https://app.torizon.io/api/v1/user_repo/targets/${MACHINE_CONFIG}-$(cat build.hash) || true
        fi

        torizoncore-builder build 2>&1 | tee build.out
        grep 'Deploying OSTree with checksum' build.out  | awk '{print $NF}' | tr -d '[:space:]' > build.hash
        rm -f build.out

	    torizoncore-builder platform push \
			--credentials credentials.zip \
			--package-name "${MACHINE_CONFIG}" \
			--package-version 1 \
			"${MACHINE_CONFIG}"
    )
done
