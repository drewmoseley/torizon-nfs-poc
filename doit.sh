#!/bin/bash

for app in wget curl jq; do
    if [ -z "$(type -path $app)" ]; then
        echo Please install $app
        set +x
        exit 1
    fi
done

if [ ! -e config.sh ]; then
    cat > config.sh <<EOF
server_ip=
server_config_dir_prefix=
client_ip=
client_config_dir_prefix=
usb_key=
api_client_id=
api_client_secret=
EOF
    echo "Please edit config.sh and set parameter values"
    exit 1
fi

source config.sh
if [ -z "${client_ip}" ]; then
    echo Please add client_ip to config.sh with the IP address or FQDN of the secondary/client board
    exit 1
fi

if [ -z "${server_ip}" ]; then
    echo Please add server_ip to config.sh with the IP address or FQDN of the primary/NFS server board
    exit 1
fi

if [ -z "${usb_key}" ]; then
    echo Please add usb_key to config.sh with the name of the USB key
    exit 1
fi

if [ -z "${api_client_id}" ] || [ -z "${api_client_secret}" ]; then
    echo Please add API credentials from  https://app.torizon.io/#/account to config.sh
    exit 1
fi

if [ -z "${server_config_dir_prefix}" ]; then
    echo Please set server_config_dir_prefix in config.sh
    exit 1
fi

if [ -z "${client_config_dir_prefix}" ]; then
    echo Please set client_config_dir_prefix in config.sh
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
                        --shared-data shared-data.tar.gz
fi

cp -f shared-data.tar.gz credentials.zip ${server_config_dir_prefix}_v1/
cp -f shared-data.tar.gz credentials.zip ${server_config_dir_prefix}_update/
cp -f shared-data.tar.gz credentials.zip ${client_config_dir_prefix}_v1/
cp -f shared-data.tar.gz credentials.zip ${client_config_dir_prefix}_update/

sed -e "s~@client-ip@~${client_ip}~" exports.in > ${server_config_dir_prefix}_v1/changes/usr/etc/exports
sed -e "s~@client-ip@~${client_ip}~" exports.in > ${server_config_dir_prefix}_update/changes/usr/etc/exports

sed -e "s~@usb-key@~${usb_key}~" 100-offline-updates-server.toml.in > ${server_config_dir_prefix}_v1/changes/usr/etc/sota/conf.d/100-offline-updates.toml
sed -e "s~@usb-key@~${usb_key}~" 100-offline-updates-server.toml.in > ${server_config_dir_prefix}_update/changes/usr/etc/sota/conf.d/100-offline-updates.toml

mkdir -p ${client_config_dir_prefix}_v1/changes/usr/etc/systemd/system/multi-user.target.wants
mkdir -p ${client_config_dir_prefix}_update/changes/usr/etc/systemd/system/multi-user.target.wants
ln -s /etc/systemd/system/multi-user.target.wants/nfs.mount \
   ${client_config_dir_prefix}_v1/changes/usr/etc/systemd/system/multi-user.target.wants/nfs.mount
ln -s /etc/systemd/system/multi-user.target.wants/nfs.mount \
   ${client_config_dir_prefix}_update/changes/usr/etc/systemd/system/multi-user.target.wants/nfs.mount
sed -s "s~@server-ip@~${server_ip}~" nfs.mount.in > ${client_config_dir_prefix}_v1/changes/usr/etc/systemd/system/nfs.mount 
sed -s "s~@server-ip@~${server_ip}~" nfs.mount.in > ${client_config_dir_prefix}_update/changes/usr/etc/systemd/system/nfs.mount 
mkdir -p ${server_config_dir_prefix}_v1/changes/nfs
mkdir -p ${server_config_dir_prefix}_update/changes/nfs

for MACHINE_CONFIG in ${server_config_dir_prefix}_v1 ${client_config_dir_prefix}_v1; do
    (
        cd $MACHINE_CONFIG
        rm -rf tezi
        torizoncore-builder build
    )
done

TDX_TOKEN=$(curl -s https://kc.torizon.io/auth/realms/ota-users/protocol/openid-connect/token \
				 -d client_id=${api_client_id} -d client_secret=${api_client_secret} \
				 -d grant_type=client_credentials | jq -r .access_token)

# Make sure ${client_config_dir_prefix}_update is first in the list so that it
# can be built and included in the build of ${server_config_dir_prefix}_update
PACKAGE_VERSION=1
EXPIRATION_DATE=$(date -d "+7 days" -u +%Y-%m-%dT%H:%M:%SZ)

for MACHINE_CONFIG in ${client_config_dir_prefix}_update ${server_config_dir_prefix}_update; do
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
			--package-version "${PACKAGE_VERSION}" \
			"${MACHINE_CONFIG}"

        BUILD_HASH=$(cat build.hash)
        PACKAGE_LENGTH=$(curl -s --header "Authorization: Bearer ${TDX_TOKEN}" --location \
					          --request GET https://app.torizon.io/api/v1/user_repo/targets.json | \
					         jq ".signed.targets[\"${MACHINE_CONFIG}-${BUILD_HASH}\"].length")

        echo Creating Lockbox
        read -d '' LOCKBOX_BODY << EOF
{
  "expiresAt": "${EXPIRATION_DATE}",
  "values": {
    "${MACHINE_CONFIG}-${BUILD_HASH}": {
      "hashes": {
        "sha256": "${BUILD_HASH}"
      },
      "length": ${PACKAGE_LENGTH},
      "custom": {
        "hardwareIds": [
          "${TORIZON_MACHINE}"
        ]
      }
    }
  }
}
EOF
        
	    curl -s --header "Authorization: Bearer ${TDX_TOKEN}" \
			--header "Content-Type: application/json" \
			--location \
			--request POST https://app.torizon.io/api/v1/admin/repo/offline-updates/${MACHINE_CONFIG}_${PACKAGE_VERSION} \
			--data "${LOCKBOX_BODY}"

        echo Creating Update media
	    torizoncore-builder platform lockbox \
			   "${MACHINE_CONFIG}_${PACKAGE_VERSION}" \
			   --credentials credentials.zip \
			   --output-directory update \
			   --force
    )
done
