FROM ubuntu:16.04

RUN apt-get update && apt-get install -y sox cdrdao ffmpeg libsox-fmt-all

COPY cdrdaowavedump.sh /usr/local/bin/cdrdaowavedump.sh
COPY cdrdaomaketoc.sh /usr/local/bin/cdrdaomaketoc.sh
COPY cdrdaowritecd.sh /usr/local/bin/cdrdaowritecd.sh

WORKDIR /share

CMD /bin/bash