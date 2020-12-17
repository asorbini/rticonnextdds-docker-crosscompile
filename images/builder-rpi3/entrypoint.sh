#!/bin/bash
set -e
printf "connextdds-builder starting up...\n"

# Load a custom init script if specified
if [ -n "${ENVRC}" ]; then
    echo "Initializing custom environment from: ${ENVRC}"
    . ${ENVRC}
fi

if [ -n "${INIT}" ]; then
    echo "Running custom startup script: ${INIT}"
    ${INIT}
fi

if [ -z "${CONNEXTDDS_ARCH}" ]; then
    echo "ERROR: no CONNEXTDDS_ARCH specified." >&2
    echo "Use -e CONNEXTDDS_ARCH=<arch> when creating the container to specify a value." >&2
    exit 1
fi

# Check that we have a valid NDDSHOME by trying to load the rtisetenv script
if ! source /rti/ndds/resource/scripts/rtisetenv_${CONNEXTDDS_ARCH}.bash; then
   echo "ERROR: failed to load RTI Connext DDS [${CONNEXTDDS_ARCH}] from /rti/ndds."  >&2
   echo "Use -v /rti/ndds=\${NDDSHOME} when creating the container to mount the required volume." >&2
   exit 1
fi

bkp_pfx=.bkp-docker-rpi

# Replace FindRTIConnextDDS.cmake with the modified version for arm.
# We will restore it once the command exits.
echo "Installing FindRTIConnextDDS.cmake for Raspberry Pi..."
if [ ! -f ${NDDSHOME}/resource/cmake/FindRTIConnextDDS.cmake${bkp_pfx} ]; then
    mv ${NDDSHOME}/resource/cmake/FindRTIConnextDDS.cmake \
       ${NDDSHOME}/resource/cmake/FindRTIConnextDDS.cmake${bkp_pfx}
fi
cp /rti/FindRTIConnextDDS_rpi.cmake \
   ${NDDSHOME}/resource/cmake/FindRTIConnextDDS.cmake

# If connextdds-py is mounted, updated the CMake dependencies to require
# CMake <=3.14, since the official binaries for CMake 3.15-3.18 don't work
# under qemu/arm, and they would require to be built from source using a
# special flag (see https://gitlab.kitware.com/cmake/cmake/-/issues/20568)
if [ -f /rti/connextdds-py/modules/CMakeLists.txt \
     -o -f /rti/connextdds-py/templates/pyproject.toml ]; then
    echo "Lowering connextdds-py dependencies to CMake 3.14..."
    cp /rti/connextdds-py/modules/CMakeLists.txt \
       /rti/connextdds-py/modules/CMakeLists.txt${bkp_pfx}
    sed -ir 's/^cmake_minimum_required\(VERSION 3.1[5-8]\)$/cmake_minimum_required(VERSION 3.14)/' \
            /rti/connextdds-py/modules/CMakeLists.txt
    cp /rti/connextdds-py/templates/pyproject.toml \
       /rti/connextdds-py/templates/pyproject.toml${bkp_pfx}
    sed -ir 's/cmake >3\.15,<=3.18\.1/cmake >=3.14,<3.15/' \
            /rti/connextdds-py/templates/pyproject.toml
fi

cleanup()
{
    # Restore original FindRTIConnextDDS.cmake
    if [ -f ${NDDSHOME}/resource/cmake/FindRTIConnextDDS.cmake${bkp_pfx} ]; then
        mv ${NDDSHOME}/resource/cmake/FindRTIConnextDDS.cmake${bkp_pfx} \
        ${NDDSHOME}/resource/cmake/FindRTIConnextDDS.cmake
        echo "Restored original FindRTIConnextDDS.cmake"
    fi

    # Restore original connextdds-py
    if [ -f /rti/connextdds-py/modules/CMakeLists.txt${bkp_pfx} \
        -o -f /rti/connextdds-py/templates/pyproject.toml${bkp_pfx} ]; then
        mv /rti/connextdds-py/modules/CMakeLists.txt${bkp_pfx} \
        /rti/connextdds-py/modules/CMakeLists.txt
        mv /rti/connextdds-py/templates/pyproject.toml${bkp_pfx} \
        /rti/connextdds-py/templates/pyproject.toml
        echo "Restored original connextdds-py dependencies"
    fi
}

# Enter base working directory
cd /rti

# Trap SIGTERM to cleanup things upon stop
trap 'cleanup' SIGTERM

# Intercept and run default command
if [ "$@" = "__default__" ]; then
    echo "Spawning a shell..."
    bash
else
    echo "Running custom command: '$@'"
    exec "$@"
fi

# Clean things up and restore original files
cleanup
