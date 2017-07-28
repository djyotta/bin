#!/bin/bash

VIDEODEVICE=/dev/video0
V4L2CTL=$(which v4l2-ctl)
BC=$(which bc)
MISSING=$(printf "%d" 0x494d5353)
NOEXIST=$(printf "%d" 0x4f4e454e)
HELP=$(printf "%d" 0x4548504c)
NOSUPPORT=$(printf "%d" 0x4855484f)
NOSTREAM=false
die(){
    if [ "$2" ]; then echo "$2" >&2; fi
    if [ $((1 == HELP)) ]; then show_help >&2; fi
    exit $1
}

show_help(){
    cat <<EOF

  usage: ${0##*/} -s WxH -f fps[:ofps] [-d video-device] [-a audio-device] [-e mencoder|ffmpeg|avconv] [-n mplayer|ffplay|avplay]
    -s frame size (see v4l2-ctl for supported frame sizes)
    -f fps (see v4l2-ctl for supported fps for given size)
    -d input video device (default $VIDEODEVICE)
    -a input audio device (if different)
    -n don't stream (but play encoded output). One of
        mplayer, ffplay, avplay, cvlc
       must be specified.
    -e encoder to use:
        ffmpeg - capture encode and stream using ffmpeg
        mencoder - capture and encode with mencoder and stream using ffmpeg
        avconv - capture encode and stream with avconv
        vlc - capture and encode with vlc, stream with ffmpeg
    -t streaming target (ie, rtmp://my-server/live:stream-id)

  Note: Every time ffmpeg/avconv, mplayer, vlc are updated they behave slightly differently!

     *  I found that mplayer can't playback streams produced by ffmpeg very well.
        This is why neither "-e vlc -n mplayer" nor "-e ffmpeg -n mplayer" work correctly (vlc uses ffmpeg to encode).
     *  ffplay seems to be the most reliable player.
     *  vlc doesn't playback at all at the moment.

  Example:
     # Use mencoder to record from /dev/video0 using pulse for audio.
     # Capture from camera at framerate of 15 fps and encode to framerate of 30 fps.
     # Play encoded video with ffplay (to test)
     ./${0##*/} -s 1280x720 -f 15:30 -e mencoder -d /dev/video0 -a pulse -n ffplay

     # Use vlc to record from /dev/video0 using pulse for audio.
     # Capture from camera at 30 fps framerate (preserved during encoding).
     # Play encoded video with ffplay (to test)
     ./${0##*/} -s 1280x720 -f 30 -e vlc -d /dev/video0 -a pulse -n ffplay

EOF
}
while getopts ":a:d:e:f:hn:s:t:v" opt; do
    case $opt in
        a)
            AUDIODEVICE=$OPTARG
            ;;
        d)
            VIDEODEVICE=$OPTARG
            ;;
        e)
            case $OPTARG in
                avconv)
                ;&
                ffmpeg)
                    FFMPEG=$(which $OPTARG) || die $NOEXIST "$OPTARG not found in PATH"
                    ;;
                mencoder)
                    MENCODER=$(which $OPTARG) || die $NOEXIST "$OPTARG not found in PATH"
                    ;;
                vlc)
                    VLC=$(which $OPTARG) || die $NOEXIST "$OPTARG not found in PATH"
                    ;;
                *)
                    die $NOSUPPORT "encoder $OPTARG not supported"
                    ;;
            esac
            ;;
        f)
            FPS=$OPTARG
            IFPS=$(echo $FPS | cut -d':' -f1)
            OFPS=$(echo $FPS | cut -d':' -f2)
            [ "${OFPS:-x}" == "x" ] && OFPS=$IFPS
            ;;
        h)
            show_help
            exit 0
            ;;
        n)
            [ "${TARGET:-x}" == "x" ] || die $HELP "-$opt is incompatibale with -t"
            NOSTREAM=true
            case $OPTARG in
                avplay)
                ;&
                ffplay)
                    FFPLAY=$(which $OPTARG) || die $NOEXIST "$OPTARG not found in PATH"
                    ;;
                mplayer)
                    MPLAYER=$(which $OPTARG) || die $NOEXIST "$OPTARG not found in PATH"
                    ;;
                vlc)
                    die $NOSUPPORT "Encoding with $OPTARG not currently supported"
                    which $OPTARG || die $NOEXIST "$OPTARG not found in PATH"
                    VLCDISPLAY="--sout-display"
                    ;;
            esac
            ;;
        s)
            WIDTH=${OPTARG%%x*}
            HEIGHT=${OPTARG##*x}
            if [ "${WIDTH=x}" == "x" ] || [ "${HEIGHT=x}" == "x" ]; then
                die 1 "size must be specified as WITHxHEIGHT (eg, 800x600)"
            fi
            ;;
        t)
            $NOSTREAM && die $HELP "-$opt is incompatibale with -n"
            TARGET=$OPTARG
            ;;
        v)
            VERBOSITY=$( ($VERBOSITY+1))
            ;;
        '?')
            die $HELP
            ;;
        ':')
            case $OPTARG in
                a)
                    die $MISSING "-$OPTARG requires ALSA device identifier as argument"
                    ;;
                d)
                    die $MISSING "-$OPTARG requires path to video device as argument"
                    ;;
                s)
                    die $MISSING "-$OPTARG requires size as WxH"
                    ;;
                e)
                    ;&
                f)
                    ;&
                n)
                    ;&
                t)
                    die $MISSING "-$OPTARG requires an argument"
                    ;;
                *)
                    die $HELP
                    ;;
            esac
            ;;
        *)
            die $HELP
            ;;
    esac
done
[ -e $BC ] || die $NOEXIST "This program depends on \"bc\" installed"
[ -e $V4L2CTL ] || die $NOEXIST "This program depends on \"v4l2\" installed"

([ "${WIDTH-x}" == "x" ] || [ "${HEIGHT-x}" == "x" ]) && die $MISSING "size must be specifed"
[ -e $VIDEODEVICE ] || die $NOEXIST "video device does not exist: $VIDEODEVICE"
[ "${FPS-x}" == "x" ] && die $MISSING "fps must be specified"
$NOSTREAM || ! [ "${TARGET:-x}" == "x" ] || die $MISSING "-t or -n must be supplied"
[ "${FFMPEG:-x}" == "x" ] && [ "${MENCODER:-x}" == "x" ] && [ "${VLC:-x}" == "x" ] && die $NOEXIST "stream -t or -n must be supplied"

$V4L2CTL -d $VIDEODEVICE -c exposure_auto_priority=0
ASPECT=$($BC <<< "scale=2; $WIDTH/$HEIGHT")

cleanup(){
    echo "Cleaning up"
    set -x
    [ "$ENCODER" ] && kill -9 $ENCODER && unset ENCODER
    set +x
}
finally(){
    set -x
    cleanup
    rm -rf $WORKING
    set +x
    return 1
}
# This puts background processes in a seperate process group
# so that the INT is caught only by the trap, and not by the
# child process.
# Here, the child process is the STREAMER, so will exit when
# the fifo reaches EOF, so we can be sure it will terminate.
trap "cleanup" INT QUIT TERM

WORKING=$(mktemp -d)
FIFO=$WORKING/inout.flv
mkfifo $FIFO

if [ "${AUDIODEVICE-x}" == "x" ]; then
    AUDIOOPTS=""
else
    if ! [ "${MENCODER-x}" == "x" ]; then
        AUDIOOPTS=":forceaudio:alsa:adevice=$AUDIODEVICE:audiorate=44100:amode=0"
    elif ! [ "${VLC-x}" == "x" ]; then
        AUDIOOPTS="--input-slave=alsa://$AUDIODEVICE"
    elif ! [ "${FFMPEG-x}" == "x" ]; then
        AUDIOOPTS="-f alsa -ac 1 -ar 44100 -i pulse"
    fi
fi

#start encoder
if ! [ "${MENCODER-x}" == "x" ]; then
    setsid $MENCODER -tv device=$VIDEODEVICE:width=$WIDTH:height=$HEIGHT:fps=$IFPS$AUDIOOPTS \
              -vf scale=-1:-10,harddup \
              -ovc x264 \
              -x264encopts preset=fast:bitrate=1000 \
              -oac mp3lame \
              -lameopts cbr:br=96 -af channels=1 \
              -o $FIFO \
              -ofps $OFPS \
              -of lavf -lavfopts format=flv \
              tv:// 2>encoder.err 1>encoder.out &
    ENCODER=$!
elif ! [ "${VLC-x}" == "x" ]; then
    VLCTRANSCODE="transcode{vcodec=h264,vb=1000,acodec=mp4a,ab=64,channels=1,samplerate=44100,fps=$OFPS}"
    VLCSTD="std{access=stream,mux=flv,dst=$FIFO}"
    [ $VLCDISPLAY ] && VLCCHAIN="#${VLCTRANSCODE}:"
    [ $VLCDISPLAY ] || VLCCHAIN="#${VLCTRANSCODE}:${VLCSTD}"
    VLCCACHING="--live-caching 300"
    VLCINTERFACE="-I dummy"
    # mjpeg-fps   --specific to your webcam
    # v4l2-chroma --specific to your webcam
    setsid $VLC $VLCINTERFACE \
           v4l2://$VIDEODEVICE \
           $VLCCACHING \
           $AUDIOOPTS \
           --mjpeg-fps=$IFPS \
           --v4l2-chroma=mjpg \
           --v4l2-fps=$IFPS \
           --v4l2-width=$WIDTH --v4l2-height=$HEIGHT \
           --sout-avcodec-strict=-2 \
           --sout="$VLCCHAIN" \
           $VLCDISPLAY \
           2>encoder.err 1>encoder.out &
    ENCODER=$!
    $NOSTREAM && [ $VLCDISPLAY ] && STREAMER=$!
elif ! [ "${FFMPEG-x}" == "x" ]; then
    if $NOSTREAM; then
        FFMPEGOUTPUT=$FIFO
    else
        FFMPEGOUTPUT=$TARGET
    fi

    #untested due to ffmpeg freezing on DELL Latitude E6400 when capturing from video devices
    setsid $FFMPEG -y $AUDIOOPTS -f video4linux2 -input_format mjpeg \
           -s ${WIDTH}x${HEIGHT} \
           -framerate $IFPS \
           -i $VIDEODEVICE \
           -c:v h264 \
           -b:v 1000k \
           -b:a 64k \
           -ac 1 \
           -r $OFPS \
           -f flv $FFMPEGOUTPUT \
           2>encoder.err 1>encoder.out &
    ENCODER=$!
    $NOSTREAM || STREAMER=$!
fi

#start streamer/player
if ! [ "${MPLAYER-x}" == "x" ]; then
    setsid $MPLAYER -aspect $ASPECT -fps $OFPS $FIFO 2>stream.err 1>stream.out &
    STREAMER=$!
#listen on fifo first
elif ! [ "${FFPLAY-x}" == "x" ]; then
    setsid $FFPLAY -autoexit -i $FIFO 2>stream.err 1>stream.out &
    STREAMER=$!
elif ! $NOSTREAM && ! [ $STREAMER ]; then
    FFMPEG=$(which ffmpeg || which avconv) || die $NOEXIST "ffmpeg/avconv not found in PATH"
    setsid $FFMPEG -i $FIFO -framerate $OFPS  -c:a copy -c:v copy -f flv "$TARGET" 2>stream.err 1>stream.out &
    STREAMER=$!
fi

: ${STREAMER:=$ENCODER}

while kill -0 $STREAMER 2>/dev/null || finally; do
    wait $STREAMER
done
