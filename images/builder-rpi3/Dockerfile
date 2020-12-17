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

RUN mkdir /rti
COPY FindRTIConnextDDS_rpi.cmake /rti
VOLUME [ "/rti/ndds" ]
VOLUME [ "/rti/connextdds-py" ]

COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]
CMD ["__default__"]
