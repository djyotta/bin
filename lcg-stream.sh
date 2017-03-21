#!/bin/bash 

VIDEODEVICE=/dev/video0
V4L2CTL=$(which v4l2-ctl)
BC=$(which bc)
NOSTREAM=false
MISSING=$(printf "%d" 0x494d5353)
NOEXIST=$(printf "%d" 0x4f4e454e)
HELP=$(printf "%d" 0x4548504c)
NOSUPPORT=$(printf "%d" 0x4855484f)

die(){
    if [ "$2" ]; then echo "$2" >&2; fi
    if [ $((1 == HELP)) ]; then show_help >&2; fi
    exit $1
}

show_help(){
	cat <<EOF

  usage: ${0##*/} -s WxH -f fps [-d video-device] [-a audio-device] [-e mencoder|ffmpeg|avconv] [-n mplayer|ffplay|avplay]
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

  Note: Every time ffmpeg/avconv, mplayer, vlc are updated they behave slightly differently!
        At time of writing the following combinations work:
		 "-e mencoder"
		 "-e mencoder -n mplayer"
		 "-e mencoder -n ffplay"
		 "-e vlc"
		 "-e vlc -n ffplay"

		I found that mplayer can't playback streams produced by ffmpeg very well.
	 	This is why "-e vlc -n mplayer" doesn't work. 
		Also even "-e mencoder" will ultimately stream with ffmpeg, so play back of the actual live stream
		won't work well with mplayer. However, both "-e mencoder" and "-e vlc" produce streams that are 
		playable with ffplay.
		Ultimately, the best encoder to use is "-e vlc", as google chrome won't play the video of the "-e mencoder" stream. :(

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
                    die $NOSUPPORT "Encoding with $OPTARG not currently supported"
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
            ;;
        h)
            show_help
            exit 0
            ;;
        n)
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
                    die $NOSUPPORT "playback with $OPTARG not currently supported"
                    VLCPLAY=$(which $OPTARG) || die $NOEXIST "$OPTARG not found in PATH"
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
$V4L2CTL -d $VIDEODEVICE -c exposure_auto_priority=0
ASPECT=$($BC <<< "scale=2; $WIDTH/$HEIGHT")

if ! [ "${FFMPEG-x}" == "x" ] && ! $NOSTREAM; then
    #currently, only ffmpeg and avconv can stream directly without fifo
    $FFMPEG $opts -f video4linux2 -framerate $FPS -r $FPS -s ${WIDTH}x${HEIGHT} -input_format mjpeg -i $VIDEODEVICE  -codec:v flv -codec:a mp3 -b:v 350k -b:a 48k -f flv $TARGET 2>encoder.err 1>encoder.out
    exit 0
fi

cleanup(){
    echo "Cleaning up"
    [ "$ENCODER" ] && kill $ENCODER
	wait $STREAMER
    rm -rf $WORKING
    exit
}
# This puts background processes in a seperate process group
# so that the INT is caught only by the trap, and not by the
# child process.
# Here, the child process is the STREAMER, so will exit when
# the fifo reaches EOF, so we can be sure it will terminate.
trap "cleanup" INT QUIT TERM
WORKING=$(mktemp -d)
FIFO=$WORKING/inout.flv
if [ "${MPLAYER-x}" == "x" ]; then
	mkfifo $FIFO
fi

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
    $MENCODER -tv device=$VIDEODEVICE:width=$WIDTH:height=$HEIGHT:fps=$FPS$AUDIOOPTS \
			  -vf scale=-1:-10,harddup \
              -ovc x264 \
			  -x264encopts preset=fast:bitrate=350:vbv_maxrate=350 \
			  -oac mp3lame \
			  -lameopts cbr:br=96 -af channels=1 \
			  -o $FIFO \
			  -of lavf -lavfopts format=flv \
			  tv:// 2>encoder.err 1>encoder.out &
elif ! [ "${VLC-x}" == "x" ]; then
    $VLC -I dummy v4l2://$VIDEODEVICE \
         --live-caching 2000 \
         $AUDIOOPTS \
         --v4l2-fps=$FPS \
         --v4l2-width=$WIDTH --v4l2-height=$HEIGHT \
         --sout="#transcode{vcodec=h264,vb=300,acodec=mp4a,ab=48,channels=1,samplerate=44100}:std{access=file,mux=flv,dst=$FIFO}" \
         2>encoder.err 1>encoder.out &
elif ! [ "${FFMPEG-x}" == "x" ] && $NOSTREAM; then
    #untested due to ffmpeg freezing on DELL Latitude E6400 when capturing from video devices
    $FFMPEG -y $AUDIOOPTS -f video4linux2 \
			-framerate -r $FPS \
			-s ${WIDTH}x${HEIGHT} \
			-input_format mjpeg \
			-i $VIDEODEVICE \
			-b:v 300k -b:a 48k \
            -f flv $FIFO 2>encoder.err 1>encoder.out &
fi
ENCODER=$!

#start streamer/player
if ! [ "${MPLAYER-x}" == "x" ]; then
	sleep 5
	setsid $MPLAYER -aspect $ASPECT -fps $FPS $FIFO 2>stream.err 1>stream.out &
elif ! [ "${FFPLAY-x}" == "x" ]; then
	setsid $FFPLAY -i $FIFO 2>stream.err 1>stream.out &
elif ! $NOSTREAM; then
	FFMPEG=$(which ffmpeg || which avconv) || die $NOEXIST "ffmpeg/avconv not found in PATH"
	setsid $FFMPEG -r $FPS -i $FIFO -c:a copy -c:v copy -f flv  $TARGET 2>stream.err 1>stream.out &
fi
STREAMER=$!

wait $ENCODER


