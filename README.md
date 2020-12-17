# rticonnextdds-docker-crosscompile

This repository provides configuration files to generate Docker images for the
cross-compilation of RTI Connext DDS applications.

## Setup

Running Docker containers from a foreign architecture requires Qemu to be available
on the system.

You can usually install Qemu via your distro's package manager, e.g. on Ubuntu:

```sh
sudo apt-get install -y qemu
```

Once Qemu is installed, you must enable hooks for it in the Docker daemon. This
can be achieved using container [hypriot/qemu-register](https://github.com/hypriot/qemu-register):

```sh
docker run --rm --privileged hypriot/qemu-register
```

## Image Use

The repository contains the following images:

| Image | Host Architecture | Supported RTI Connext DDS Targets |
|-------|-------------------|-------------------------|
|`rticonnextdds-builder-rpi3`|`armv7`|`armv7Linuxgcc7.3.0`|

Images can be built using the `docker build` command, e.g.:

```sh
docker build -t rticonnextdds-builder-rpi3 \
                rticonnextdds-docker-crosscompile/images/builder-rpi3

```

All images expect an RTI Connext DDS installation to be mounted via volume
`/rti/ndds`. The target architecture can be specified via environment variable
`CONNEXTDDS_ARCH` (passed via `-e CONNEXTDDS_ARCH=<arch>`), or a default value
for the image will be used.

You can use the `--rm` option to automatically delete the container after
completion, e.g.:

```sh
# Mount the current directory to build binaries for Raspberry Pi 3
docker run --rm -ti \
           -v ${NDDSHOME}:/rti/ndds \
           -v $(pwd):/work \
           rticonnextdds-builder-rpi3
```

**Please be aware that compilation in the emulated environments will be
extremely slow (a few orders of magnitude slower than native builds).**

By default, the containers run commands as root, and generated files will have
root-level permissions in the host. If you want files to be generated with the
correct permissions you should use variables `USER_ID` and `GROUP_ID` to
specify the user and group IDs to use inside the container.

For example, to match the current shell user and group (assumed to have the
same name as the user):

```sh
docker run --rm -ti \
           -v ${NDDSHOME}:/rti/ndds \
           -v $(pwd):/work \
           -e USER_ID=$(id -u $(whoami)) \
           -e GROUP_ID=$(getent group $(whoami) | cut -d: -f3) \
           rticonnextdds-builder-rpi3
```

### rticonnextdds-builder-rpi3

This image is based on [balenalib/raspberrypi3-debian:build](https://hub.docker.com/r/balenalib/raspberrypi3-debian).
It provides an `armv7` build environment running Raspbian Buster that can be
used to build applications for Raspberry Pi 3.

The entry point script supports the specification of custom behavior via the
following environment variables:

| Variable | Description |
|----------|-------------|
|`ENVRC`|Custom environment script that will be sourced on start up.|
|`INIT`|Custom initialization script that will be run on start up (after `ENVRC`).|

The entry point script will copy a modified version of `FindRTIConnextDDS.cmake`
into the mounted `NDDSHOME`, replacing the stock version with one modified to
support `armv7l` and `aarch64` architectures. The original file will be renamed
and restored when the container exists.

The image also supports building `connextdds-py` by mounting volume
`/rti/connextdds-py` with the contents of the `connextdds-py` git repository.

If `connextdds-py` is mounted, the container will temporarily modify `connextdds-py`'s
dependencies, by downgrading CMake from version 3.18 to version 3.14.
The original configuration will be restored on exit.

The need for this change stems from [a problem with stock builds of CMake](https://gitlab.kitware.com/cmake/cmake/-/issues/20568)
between versions 3.15 and 3.18 that prevents them from working under emulated arm
architectures.
The only solution is to rebuild CMake with `-D_FILE_OFFSET_BITS=64`, so a
version earlier than 3.15 is used instead to same time.

## Usage Examples

### Build connextdds-py for Raspberry Pi

On a system with RTI Connext DDS host `x64Linux`, and target `armv7Linuxgcc7.3.0`:

```sh
# Load RTI Connext DDS in environment
source /path/to/rti_connext_dds.6.0.1/resource/scripts/rtisetenv_armv7Linuxgcc7.3.0.bash

# Clone connextdds-py
git clone --recurse-submodules https://github.com/rticommunity/connextdds-py.git

# Start an ephemeral container to build connextdds-py for Raspberry Pi
docker run --rm -ti \
             -v ${NDDSHOME}:/rti/ndds \
             -v connextdds-py:/rti/connextdds-py \
             rticonnextdds-builder-rpi3

# Inside the container, enter connextdds-py/, configure the project, and
# build a wheel. This will likely take several hours. You can increase
# the number of parallel jobs by passing -j<n> to configure.py, keeping
# in mind that the compilation is memory-heavy and you might run out of memory
# if too many jobs are spawned concurrently.
cd /rti/connextdds-py
python3 configure.py ${CONNEXTDDS_ARCH}
pip3 wheel .
```

## Other Resources

- [dockcross](https://github.com/dockcross/dockcross) provides containers for an
  x86_64 host to cross-compile binaries for several different target architectures.
