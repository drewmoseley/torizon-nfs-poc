#!/bin/bash

source $(dirname $0)/utils.sh
                              
verify_installed_apps
create_or_verify_config
setup_torizoncore_builder
setup_server_config_files

run_torizoncore_builder -h
exit 1

TDX_TOKEN=$(curl -s https://kc.torizon.io/auth/realms/ota-users/protocol/openid-connect/token \
				 -d client_id=${api_client_id} -d client_secret=${api_client_secret} \
				 -d grant_type=client_credentials | jq -r .access_token)
PACKAGE_VERSION=1
EXPIRATION_DATE=$(date -d "+7 days" -u +%Y-%m-%dT%H:%M:%SZ)

torizoncore_builder_build ${server_config_dir_prefix}_v1 ${TDX_TOKEN}
torizoncore_builder_build ${client_config_dir_prefix}_v1 ${TDX_TOKEN}
torizoncore_builder_build ${server_config_dir_prefix}_update ${TDX_TOKEN}
torizoncore_builder_build ${client_config_dir_prefix}_update ${TDX_TOKEN}
torizoncore_builder_push  ${server_config_dir_prefix}_update ${PACKAGE_VERSION}
torizoncore_builder_push  ${client_config_dir_prefix}_update ${PACKAGE_VERSION}
torizoncore_builder_define_lockbox ${client_config_dir_prefix}_update ${TDX_TOKEN} ${PACKAGE_VERSION} ${EXPIRATION_DATE} ${client_machine}
torizoncore_builder_define_lockbox ${server_config_dir_prefix}_update ${TDX_TOKEN} ${PACKAGE_VERSION} ${EXPIRATION_DATE} ${server_machine}
torizoncore_builder_build_lockbox ${client_config_dir_prefix}_update ${PACKAGE_VERSION}
torizoncore_builder_build_lockbox ${server_config_dir_prefix}_update ${PACKAGE_VERSION}
