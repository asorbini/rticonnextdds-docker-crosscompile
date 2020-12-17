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
FROM balenalib/raspberrypi3-debian:build

RUN DEBIAN_FRONTEND=noninteractive \
    apt-get update
RUN DEBIAN_FRONTEND=noninteractive \
    apt-get install apt-utils
RUN DEBIAN_FRONTEND=noninteractive \
    apt-get install psmisc
RUN DEBIAN_FRONTEND=noninteractive \
   apt-get install cmake
RUN DEBIAN_FRONTEND=noninteractive \
    apt-get install python3-pip
RUN pip3 install wheel
RUN pip3 install setuptools
RUN pip3 install cmake
RUN pip3 install patchelf-wrapper
RUN DEBIAN_FRONTEND=noninteractive \
    apt-get install sudo

RUN mkdir /rti
COPY FindRTIConnextDDS_rpi.cmake /rti
VOLUME [ "/rti/ndds" ]
VOLUME [ "/rti/connextdds-py" ]

ENV CONNEXTDDS_ARCH=armv7Linuxgcc7.3.0

COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]
CMD ["__default__"]
