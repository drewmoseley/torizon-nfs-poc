#!/bin/bash
#
# Wrapper script for torizoncore-builder.
# This is more cleanly called from bash scripts, functions, etc
#

for dirbase in . ..; do
    if [ -e "${dirbase}/tcb-env-setup.sh" ]; then
        TCB_ENV="$(readlink -f ${dirbase}/tcb-env-setup.sh)"
        break
    fi
done

# Specify docker volume name - this allows torizoncore-builder
# to support multiple configurations simultaneously
TCB_SETUP_OPTS="-s $(basename $(pwd))"

if docker images | grep -q torizoncore-builder; then
    TCB_SETUP_OPTS="${TCB_SETUP_OPTS} -a local"
else
    echo Downloading torizoncore-builder image
    TCB_SETUP_OPTS="${TCB_SETUP_OPTS} -a remote"
fi

#
# From here down we are providing passthrough options for Docker
#
TCB_SETUP_OPTS="${TCB_SETUP_OPTS} -- "

IMAGES_DIR="$(readlink -f ${dirbase}/images)"
TCB_SETUP_OPTS="${TCB_SETUP_OPTS} -v ${IMAGES_DIR}:/images"

CREDENTIALS="$(readlink -f ${dirbase})/credentials.zip"
TCB_SETUP_OPTS="${TCB_SETUP_OPTS} -v ${CREDENTIALS}:/credentials.zip"

shopt -s expand_aliases
. ${TCB_ENV} ${TCB_SETUP_OPTS}
torizoncore-builder "$@"
