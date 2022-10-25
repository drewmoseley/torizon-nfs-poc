#!/bin/bash

TOP_DIR=$(readlink -f $(dirname $0))
source ${TOP_DIR}/utils.sh

verify_installed_apps
create_or_verify_config
setup_torizoncore_builder
setup_server_config_files

torizoncore_builder_build ${server_config_dir_prefix}_v1 ${TDX_TOKEN}
torizoncore_builder_build ${client_config_dir_prefix}_v1 ${TDX_TOKEN}
torizoncore_builder_build ${server_config_dir_prefix}_update ${TDX_TOKEN}
torizoncore_builder_build ${client_config_dir_prefix}_update ${TDX_TOKEN}
torizoncore_builder_push  ${server_config_dir_prefix}_update ${package_version}
torizoncore_builder_push  ${client_config_dir_prefix}_update ${package_version}
torizoncore_builder_define_lockbox ${client_config_dir_prefix}_update ${TDX_TOKEN} ${package_version} ${EXPIRATION_DATE} ${client_machine}
torizoncore_builder_define_lockbox ${server_config_dir_prefix}_update ${TDX_TOKEN} ${package_version} ${EXPIRATION_DATE} ${server_machine}
torizoncore_builder_build_lockbox ${client_config_dir_prefix}_update ${package_version}
torizoncore_builder_build_lockbox ${server_config_dir_prefix}_update ${package_version}
