#!/bin/bash
################################################################################
# (c) 2020 Copyright, Real-Time Innovations, Inc. (RTI)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################

################################################################################
# General helper functions
################################################################################

_bkp_pfx=.bkp-docker-rpi

_backup_file()
{
    if [ ! -f ${2}${_bkp_pfx} ]; then
        ${1} -v ${2} ${2}${_bkp_pfx}
    fi
}

_restore_file()
{
    if [ -f ${1}${_bkp_pfx} ]; then
        mv -v ${1}${_bkp_pfx} ${1}
    fi
}

################################################################################
# Connext DDS Helpers
################################################################################

_detect_connextdds()
{
    # Check that an RTI Connext DDS target was specified
    if [ -z "${CONNEXTDDS_ARCH}" ]; then
        echo "ERROR: no RTI Connext DDS target specified." >&2
        echo "Use -e CONNEXTDDS_ARCH=<arch> when creating the container to specify a value." >&2
        exit 1
    fi

    # Check that we have a valid NDDSHOME by trying to load the RTI Connext DDS
    # into the environment using rtisetenv_*.bash
    if ! source /rti/ndds/resource/scripts/rtisetenv_${CONNEXTDDS_ARCH}.bash; then
    echo "ERROR: failed to load RTI Connext DDS [${CONNEXTDDS_ARCH}] from /rti/ndds."  >&2
    echo "Use '-v \${NDDSHOME}:/rti/ndds' when creating the container to mount the required volume." >&2
    exit 1
    fi
}

_detect_connextddspy()
{
    # Check if connextdds-py has been mounted
    if [ -f /rti/connextdds-py/modules/CMakeLists.txt \
        -o -f /rti/connextdds-py/templates/pyproject.toml ]; then
        echo "Found connextdds-py under /rti/connextdds-py"
        CONNEXTDDSPY=connextdds-py-enabled
    fi
}

################################################################################
# Raspberry Pi Helpers
################################################################################

_builder_backup_rpi()
{
    _backup_file mv ${NDDSHOME}/resource/cmake/FindRTIConnextDDS.cmake
    if [ -n "${CONNEXTDDSPY}" ]; then
        _backup_file cp /rti/connextdds-py/modules/CMakeLists.txt
        _backup_file cp /rti/connextdds-py/templates/pyproject.toml
    fi
}

_builder_cleanup_rpi()
{
    _restore_file ${NDDSHOME}/resource/cmake/FindRTIConnextDDS.cmake
    _restore_file /rti/connextdds-py/modules/CMakeLists.txt
    _restore_file /rti/connextdds-py/templates/pyproject.toml
}

_patch_rpi()
{
    _builder_backup_rpi

    # Replace FindRTIConnextDDS.cmake with the modified version for armv7.
    # We will restore it once the command exits.
    echo "Installing FindRTIConnextDDS.cmake for Raspberry Pi..."
    cp /rti/FindRTIConnextDDS_rpi.cmake \
       ${NDDSHOME}/resource/cmake/FindRTIConnextDDS.cmake

    # If connextdds-py is mounted, updated the CMake dependencies to require
    # CMake <=3.14, since the official binaries for CMake 3.15-3.18 don't work
    # under qemu/arm, and they would require to be built from source using a
    # special flag (see https://gitlab.kitware.com/cmake/cmake/-/issues/20568)
    if [ -n "${CONNEXTDDSPY}" ]; then
        echo "Lowering connextdds-py dependencies to CMake 3.14..."
        sed -ir 's/^cmake_minimum_required\(VERSION 3.1[5-8]\)$/cmake_minimum_required(VERSION 3.14)/' \
                /rti/connextdds-py/modules/CMakeLists.txt
        sed -ir 's/cmake >3\.15,<=3.18\.1/cmake >=3.14,<3.15/' \
                /rti/connextdds-py/templates/pyproject.toml
    fi

    CLEANUP=_builder_cleanup_rpi
}

################################################################################
# Check if we should run the command with a specific UID and GID. If so,
# make sure that no user nor group exist with the specified value, then
# create them, and restart this script with the requested user
################################################################################

if [ -n "${USER_ID}" -a "${USER_ID}" != "${UID}" ]; then
    # Check that a GID was also specified
    if [ -z "${GROUP_ID}" ]; then
        echo "No GROUP_ID specified. Both USER_ID and GROUP_ID must be specified." >&2
        exit 1
    fi
    echo "Running command as ${HOST_USER:=dsuser}:${HOST_GROUP:=rti} (${USER_ID}:${GROUP_ID}:${HOME_DIR:=/rti})"
    if [ -n "${existing_user:=$(getent passwd | cut -d: -f1,3 | grep ${USER_ID})}" ]; then
        # A user already exists with the specified UID, delete it
        userdel -f $(echo ${existing_user} | cut -d: -f1)
    fi
    if [ -n "${existing_group:=$(getent group | cut -d: -f1,3 | grep ${GROUP_ID})}" ]; then
        # A group already exists with the specified GID, delete it
        groupdel $(echo ${existing_group} | cut -d: -f1)
    fi
    # Add a new group with the requested GID
    groupadd -g ${GROUP_ID} ${HOST_GROUP}
    # Add a new user with the requested UID
    useradd -l -u ${USER_ID} -g ${HOST_GROUP} -d ${HOME_DIR} -s /bin/bash ${HOST_USER}
    chown ${HOST_USER}:${HOST_GROUP} ${HOME_DIR} ${HOME_DIR}/*
    # save current environment (bar USER, UID, and HOME)
    rm -f ${HOME_DIR}/.bashenv
    echo "export \\" >> ${HOME_DIR}/.bashenv
    env | grep -vE "^(USER|UID|HOME)=" | sed -r "s/^(.*)$/\1 \\\/g" >> ${HOME_DIR}/.bashenv
    echo "_RELOADED=y" >> ${HOME_DIR}/.bashenv
    if [ ! -f ${HOME_DIR}/.profile ] ||
       ! grep "\. ${HOME_DIR}/\.bashenv" ${HOME_DIR}/.profile 2>/dev/null; then
       printf "%s\n" ". ${HOME_DIR}/.bashenv" >> ${HOME_DIR}/.profile
    fi

    sudo -i -u ${HOST_USER} /bin/bash -c "/entrypoint.sh $@"
    rc=$?
    exit ${rc}
fi

################################################################################
# Run entrypoint script
################################################################################

set -e

echo "rticonnextdds-builder starting up as user ${USER}..."

# Load custom environment and init scripts, if specified
if [ -n "${ENVRC}" ]; then
    echo "Initializing custom environment from: ${ENVRC}"
    . ${ENVRC}
fi
if [ -n "${INIT}" ]; then
    echo "Running custom startup script: ${INIT}"
    ${INIT}
fi

_detect_connextdds

_detect_connextddspy

# Apply architecture-specific "patches"
case $(uname -m) in
    armv7l)
        _patch_rpi
        ;;
    *)
        ::
esac

# Trap SIGTERM to cleanup things when container is stopped
[ -z "${CLEANUP}" ] || trap ${CLEANUP} SIGTERM

# Enter base working directory
cd /rti

# Generate a runner script so that we may invoke it from
# a custom user if needed
# Intercept and run default command or a custom one (if specified)
if [ "$@" = "__default__" ]; then
    echo "Spawning a shell..."
    bash
    rc=$?
else
    echo "Running custom command: '$@'"
    exec "$@"
    rc=$?
fi

# Clean things up and restore original files if needed
[ -z "${CLEANUP}" ] || ${CLEANUP}

exit ${rc}
