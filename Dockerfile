FROM ubuntu:16.04

RUN apt-get update && apt-get install -y software-properties-common
RUN add-apt-repository ppa:jonathonf/ffmpeg-3

RUN apt-get update && \
    apt-get install -y \
        cdrdao \
        ffmpeg \
        libsox-fmt-all \
        mplayer \
        sox \
        vlc \
    && \
    :

COPY cdrdaowavedump.sh /usr/local/bin/cdrdaowavedump
COPY cdrdaomaketoc.sh /usr/local/bin/cdrdaomaketoc
COPY cdrdaowritecd.sh /usr/local/bin/cdrdaowritecd
COPY lcg-stream.sh /usr/local/bin/lcg-stream

WORKDIR /share

CMD /bin/bash