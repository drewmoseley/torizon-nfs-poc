#!/bin/bash

TOP_DIR=$(readlink -f $(dirname $0))
source ${TOP_DIR}/utils.sh

verify_installed_apps
create_or_verify_config
setup_torizoncore_builder
setup_server_config_files
setup_client_config_files

# Build both V1 images
torizoncore_builder_build ${server_config_dir_prefix}_v1 ${TDX_TOKEN}
torizoncore_builder_build ${client_config_dir_prefix}_v1 ${TDX_TOKEN}

# Build the client update image and lockbox
torizoncore_builder_build ${client_config_dir_prefix}_update ${TDX_TOKEN}
torizoncore_builder_push  ${client_config_dir_prefix}_update ${package_version}
torizoncore_builder_define_lockbox ${client_config_dir_prefix}_update ${TDX_TOKEN} ${EXPIRATION_DATE} ${client_machine}
torizoncore_builder_build_lockbox ${client_config_dir_prefix}_update

# Copy the lockbox into the server changes directory for inclusion in its image
mkdir -p ${server_config_dir_prefix}_update/changes/nfs
tar --transform 's/update/update_secondary/' \
    -C ${client_config_dir_prefix}_update/ \
    -cf ${server_config_dir_prefix}_update/changes/nfs/update_secondary.tar \
    update

# Build the server update image and lockbox containing the client update lockbox
torizoncore_builder_build ${server_config_dir_prefix}_update ${TDX_TOKEN}
torizoncore_builder_push  ${server_config_dir_prefix}_update ${package_version}
torizoncore_builder_define_lockbox ${server_config_dir_prefix}_update ${TDX_TOKEN} ${EXPIRATION_DATE} ${server_machine}
torizoncore_builder_build_lockbox ${server_config_dir_prefix}_update
