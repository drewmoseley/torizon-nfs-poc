SOURCED=0
if [ -n "$BASH_VERSION" ]; then
    (return 0 2>/dev/null) && SOURCED=1
fi
if [ "$SOURCED" = "0" ]; then
    echo "Error: don't run $0, source it."
    exit 1
fi

verify_installed_apps() {
    for app in wget curl jq; do
        if [ -z "$(type -path $app)" ]; then
            echo Please install $app
            set +x
            exit 1
        fi
    done
}

create_or_verify_config() {
    if [ ! -e config.sh ]; then
        cat > config.sh <<EOF
server_ip=""
server_config_dir_prefix=""
server_machine=""
client_ip=""
client_config_dir_prefix=""
client_machine=""
usb_key=""
api_client_id=""
api_client_secret=""
package_version=""
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

    if [[ ${api_client_id} == *"provision"* ]] || [[ ${api_client_id} != *"api-minimal"* ]]; then
	echo Please add an API client with api-minimal access type
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

    if [ -z "${server_machine}" ]; then
        echo Please set server_machine in config.sh
        exit 1
    fi

    if [ -z "${client_machine}" ]; then
        echo Please set client_machine in config.sh
        exit 1
    fi

    if [ -z "${package_version}" ]; then
        echo Please set package_version in config.sh
        exit 1
    fi
}

setup_torizoncore_builder() {
    if [ ! -e credentials.zip ]; then
        echo Please download account credentials from \"https://app.torizon.io/#/account\" to \"$(pwd)/credentials.zip\"
        exit 1
    fi

    if [ ! -e tcb-env-setup.sh ]; then
        wget https://raw.githubusercontent.com/toradex/tcb-env-setup/master/tcb-env-setup.sh
    fi

    TCB=${TOP_DIR}/tcb.sh
    LOG=${TOP_DIR}/build-log.txt
    rm -f ${LOG}
    TDX_TOKEN=$(curl -s https://kc.torizon.io/auth/realms/ota-users/protocol/openid-connect/token \
				 -d client_id=${api_client_id} -d client_secret=${api_client_secret} \
				 -d grant_type=client_credentials | jq -r .access_token)
    EXPIRATION_DATE=$(date -d "+7 days" -u +%Y-%m-%dT%H:%M:%SZ)

    get_torizon_shared_data
}

get_torizon_shared_data() {
    if [ ! -e shared-data.tar.gz ]; then
        echo -n "Getting platform provisioning data "
        ${TCB} platform provisioning-data \
               --credentials /credentials.zip \
               --shared-data /shared-data/shared-data.tar.gz >> ${LOG} 2>&1
        echo "--- rc=$?"
    fi
}

setup_server_config_files() {
    sed -e "s~@client-ip@~${client_ip}~" exports.in > ${server_config_dir_prefix}_v1/changes/usr/etc/exports
    sed -e "s~@client-ip@~${client_ip}~" exports.in > ${server_config_dir_prefix}_update/changes/usr/etc/exports
    mkdir -p ${server_config_dir_prefix}_v1/changes/nfs
    mkdir -p ${server_config_dir_prefix}_update/changes/nfs
    mkdir -p ${server_config_dir_prefix}_v1/changes/usr/etc/sota/conf.d/
    mkdir -p ${server_config_dir_prefix}_update/changes/usr/etc/sota/conf.d/
    sed -e "s~@offline-update-path@~/var/rootdirs/media/${usb_key}/update~" \
        100-offline-updates.toml.in \
        > ${server_config_dir_prefix}_v1/changes/usr/etc/sota/conf.d/100-offline-updates.toml
    sed -e "s~@offline-update-path@~/var/rootdirs/media/${usb_key}/update~" \
        100-offline-updates.toml.in \
        > ${server_config_dir_prefix}_update/changes/usr/etc/sota/conf.d/100-offline-updates.toml
    mkdir -p ${server_config_dir_prefix}_v1/changes/usr/etc/greenboot/check/required.d/
    mkdir -p ${server_config_dir_prefix}_update/changes/usr/etc/greenboot/check/required.d/
    cp 99-nfs-server-coordinated-update.sh ${server_config_dir_prefix}_v1/changes/usr/etc/greenboot/check/required.d/
    cp 99-nfs-server-coordinated-update.sh ${server_config_dir_prefix}_update/changes/usr/etc/greenboot/check/required.d/
}

setup_client_config_files() {
    mkdir -p ${client_config_dir_prefix}_v1/changes/usr/etc/systemd/system
    mkdir -p ${client_config_dir_prefix}_update/changes/usr/etc/systemd/system
    sed -s "s~@server-ip@~${server_ip}~" nfs.mount.in > ${client_config_dir_prefix}_v1/changes/usr/etc/systemd/system/nfs.mount
    sed -s "s~@server-ip@~${server_ip}~" nfs.mount.in > ${client_config_dir_prefix}_update/changes/usr/etc/systemd/system/nfs.mount
    cp nfs.automount.in ${client_config_dir_prefix}_v1/changes/usr/etc/systemd/system/nfs.automount
    cp nfs.automount.in ${client_config_dir_prefix}_update/changes/usr/etc/systemd/system/nfs.automount
    mkdir -p ${client_config_dir_prefix}_v1/changes/usr/etc/sota/conf.d/
    mkdir -p ${client_config_dir_prefix}_update/changes/usr/etc/sota/conf.d/
    sed -e "s~@offline-update-path@~/nfs/update~" \
        100-offline-updates.toml.in \
        > ${client_config_dir_prefix}_v1/changes/usr/etc/sota/conf.d/100-offline-updates.toml
    sed -e "s~@offline-update-path@~/nfs/update~" \
        100-offline-updates.toml.in \
        > ${client_config_dir_prefix}_update/changes/usr/etc/sota/conf.d/100-offline-updates.toml

    mkdir -p ${client_config_dir_prefix}_v1/changes/usr/etc/systemd/system/multi-user.target.wants
    mkdir -p ${client_config_dir_prefix}_update/changes/usr/etc/systemd/system/multi-user.target.wants
    ln -sf /etc/systemd/system/nfs.automount \
       ${client_config_dir_prefix}_v1/changes/usr/etc/systemd/system/multi-user.target.wants/nfs.automount
    ln -sf /etc/systemd/system/nfs.automount \
       ${client_config_dir_prefix}_update/changes/usr/etc/systemd/system/multi-user.target.wants/nfs.automount

    mkdir -p ${client_config_dir_prefix}_v1/changes/usr/etc/greenboot/check/required.d/
    mkdir -p ${client_config_dir_prefix}_update/changes/usr/etc/greenboot/check/required.d/
    cp 99-nfs-client-coordinated-update.sh ${client_config_dir_prefix}_v1/changes/usr/etc/greenboot/check/required.d/
    cp 99-nfs-client-coordinated-update.sh ${client_config_dir_prefix}_update/changes/usr/etc/greenboot/check/required.d/

    # Disable aktualizr as a daemon. We do this by adding a ConditionPathExists on a nonexistent file
    mkdir -p ${client_config_dir_prefix}_v1/changes/usr/etc/systemd/system/aktualizr-torizon.service.d
    mkdir -p ${client_config_dir_prefix}_update/changes/usr/etc/systemd/system/aktualizr-torizon.service.d
    cp aktualizr-override.conf ${client_config_dir_prefix}_v1/changes/usr/etc/systemd/system/aktualizr-torizon.service.d/override.conf
    cp aktualizr-override.conf ${client_config_dir_prefix}_update/changes/usr/etc/systemd/system/aktualizr-torizon.service.d/override.conf
}

torizoncore_builder_build() {
    if [ $# != 2 ]; then
        echo "Usage: ${FUNCNAME[0]} MACHINE_CONFIG_DIR TDX_TOKEN"
        exit 1
    fi
    local machine_config="${1}"
    local tdx_token="${2}"
    
    cd ${machine_config}
    rm -rf tezi
    if [ -e "build.hash" ]; then
        local build_hash=$(cat build.hash)
        if [ -n "${build_hash}" ]; then
            echo -n "Deleting image ${machine_config}-${build_hash} "
            status_code=$(curl -s -w '%{http_code}' --header "Authorization: Bearer ${TDX_TOKEN}" \
			                   --header "Content-Type: application/json" \
			                   --location \
			                   --request DELETE https://app.torizon.io/api/v1/user_repo/targets/${machine_config}-${build_hash} || true)
            echo "--- rc=${status_code}"
        fi
    fi
    echo -n "Running \"torizoncore-builder build\" for ${machine_config}-"
    ${TCB} build > build.out 2>&1
    grep 'Deploying OSTree with checksum' build.out  | awk '{print $NF}' | tr -d '[:space:]' > build.hash
    cat build.out >> ${LOG} 2>&1
    rm -f build.out
    echo "$(cat build.hash) --- rc=$?"
    cd - >/dev/null
}

torizoncore_builder_push() {
    if [ $# != 2 ]; then
        echo "Usage: ${FUNCNAME[0]} MACHINE_CONFIG_DIR PACKAGE_VERSION"
        exit 1
    fi
    local machine_config="${1}"
    local package_version="${2}"
    
    cd ${machine_config}
    echo -n "Running \"torizoncore-builder push\" for ${machine_config}_${package_version}-$(cat build.hash) "
	${TCB} platform push \
		   --credentials /credentials.zip \
		   --package-name "${machine_config}" \
		   --package-version "${package_version}" \
		   "${machine_config}" >> ${LOG} 2>&1
    echo "--- rc=$?"
    cd - >/dev/null
}

# Use the server API to _define_ the lockbox.
# currently tcb does not have this functionality
torizoncore_builder_define_lockbox() {
    if [ $# != 4 ]; then
        echo "Usage: ${FUNCNAME[0]} MACHINE_CONFIG_DIR TDX_TOKEN EXPIRATION_DATE TORIZON_MACHINE"
        exit 1
    fi
    local machine_config="${1}"
    local tdx_token="${2}"
    local expiration_date="${3}"
    local torizon_machine="${4}"

    cd ${machine_config}
    local build_hash=$(cat build.hash)
    local package_length=$(curl -s --header "Authorization: Bearer ${TDX_TOKEN}" --location \
					            --request GET https://app.torizon.io/api/v1/user_repo/targets.json | \
					           jq ".signed.targets[\"${machine_config}-${build_hash}\"].length")

    echo -n "Defining Lockbox via API for ${machine_config} "
    read -d '' lockbox_body << EOF
{
  "expiresAt": "${expiration_date}",
  "values": {
    "${machine_config}-${build_hash}": {
      "hashes": {
        "sha256": "${build_hash}"
      },
      "length": ${package_length},
      "custom": {
        "hardwareIds": [
          "${torizon_machine}"
        ]
      }
    }
  }
}
EOF

	status_code=$(curl -s -w '%{http_code}' --header "Authorization: Bearer ${TDX_TOKEN}" \
		               --header "Content-Type: application/json" \
		               --location \
		               --request POST https://app.torizon.io/api/v1/admin/repo/offline-updates/${machine_config} \
		               --data "${lockbox_body}")
    echo "--- rc=${status_code}"
    cd - >/dev/null
}

torizoncore_builder_build_lockbox() {
    if [ $# != 1 ]; then
        echo "Usage: ${FUNCNAME[0]} MACHINE_CONFIG_DIR"
        exit 1
    fi
    local machine_config="${1}"
    cd ${machine_config}
    echo -n "Building Lockbox for ${machine_config} "
	${TCB} platform lockbox \
		   "${machine_config}" \
		   --credentials /credentials.zip \
		   --output-directory update \
		   --force >> ${LOG} 2>&1
    echo "--- rc=$?"
    cd - >/dev/null
}
