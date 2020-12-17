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
# Helper functions to make copies of modified files and to restore them on exit
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

_builder_backup()
{
    echo "Backing up original files..."
    _backup_file mv ${NDDSHOME}/resource/cmake/FindRTIConnextDDS.cmake
    if [ -n "${CONNEXTDDSPY}" ]; then
        _backup_file cp /rti/connextdds-py/modules/CMakeLists.txt
        _backup_file cp /rti/connextdds-py/templates/pyproject.toml
    fi
}

_builder_cleanup()
{
    # Restore original FindRTIConnextDDS.cmake
    _restore_file ${NDDSHOME}/resource/cmake/FindRTIConnextDDS.cmake
    echo "Restored original FindRTIConnextDDS.cmake"

    _restore_file /rti/connextdds-py/modules/CMakeLists.txt
    echo "Restored original connextdds-py dependencies"
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
    echo "Running command with UID=${USER_ID} and GID=${GROUP_ID}"
    if [ -n "${existing_user:=$(getent passwd | cut -d: -f1,3 | grep ${USER_ID})}" ]; then
        # A user already exists with the specified UID, delete it
        userdel -f $(echo ${existing_user} | cut -d: -f1)
    fi
    if [ -n "${existing_group:=$(getent group | cut -d: -f1,3 | grep ${GROUP_ID})}" ]; then
        # A group already exists with the specified GID, delete it
        groupdel $(echo ${existing_group} | cut -d: -f1)
    fi
    # Add a new group with the requested GID
    groupadd -g ${GROUP_ID} rti
    # Add a new user with the requested UID
    useradd -l -u ${USER_ID} -g rti -d /rti -s /bin/bash dsuser
    chown dsuser:rti /rti /rti/ndds /rti/connextdds-py
    # save current environment (bar USER, UID, and HOME)
    rm -f /rti/.bashrc-env
    echo "export \\" >> /rti/.bashrc-env
    env | grep -vE "^(USER|UID|HOME)=" | sed -r "s/^(.*)$/\1 \\\/g" >> /rti/.bashrc-env
    echo "_RELOADED=y" >> /rti/.bashrc-env
    # printf "%s\n" "_RELOADED=y /entrypoint.sh $@" >> /rti/.bashrc-rti
    if [ ! -f /rti/.bashrc ] || ! grep "\. /rti/\.bashrc-rti" /rti/.bashrc 2>/dev/null; then
        (cat <<EOF
. /rti/.bashrc-env
EOF
) >> /rti/.profile
    fi

    sudo -i -u dsuser /bin/bash -c "/entrypoint.sh $@"
    rc=$?
    # _builder_cleanup
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

# Check if connextdds-py has been mounted
if [ -f /rti/connextdds-py/modules/CMakeLists.txt \
     -o -f /rti/connextdds-py/templates/pyproject.toml ]; then
    echo "Found connextdds-py under /rti/connextdds-py"
    CONNEXTDDSPY=connextdds-py-enabled
fi

_builder_backup

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

# Enter base working directory
cd /rti

# Trap SIGTERM to cleanup things when container is stopped
trap _builder_cleanup SIGTERM

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

# Clean things up and restore original files
_builder_cleanup

exit ${rc}
