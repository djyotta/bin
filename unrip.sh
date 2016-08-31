#!/bin/bash
#
# A simple scriptlet to prepare a file ripped with ./rip.sh for authoring
#
usage(){
	cat <<EOF
    usage: ./${0##*/} FILE

    FILE should be a video file which already has streams suitable for VOB
      video stream: mpeg2video
      audio: uncompressed pcm
    If your streams need to be converted, don't bother with this script.
    Instead, use ffmpeg to convert the streams to the correct format.

    Allowed formats for DVDs
    -------------------------------------------------------------------------
    ||||||||||||| Aspect ( -s ) | PAL/NTSC | FPS ( -r ) | Resolution ( -s ) |
    -------------------------------------------------------------------------
    | Widscreen | 1.78          | NTSC     | 29.97      | 720x480           |
    |           |               ---------------------------------------------
    |           |               | PAL      | 25         | 720x576           |
    -------------------------------------------------------------------------
    | Standard  | 1.33          | NTSC     | 29.97      | 720x480           |
    |           |               |          |            ---------------------
    |           |               |          |            | 704x480           |
    |           |               |          |            ---------------------
    |           |               |          |            | 352x480           |
    |           |               |          |            ---------------------
    |           |               |          |            | 352x240           |
    |           |               ---------------------------------------------
    |           |               | PAL      | 25         | 720x576           |
    |           |               |          |            ---------------------
    |           |               |          |            | 704x576           |
    |           |               |          |            ---------------------
    |           |               |          |            | 352x576           |
    |           |               |          |            ---------------------
    |           |               |          |            | 352x288           |
    -------------------------------------------------------------------------
    # Example:
    ffmpeg -i FILE -f mpeg2video -acodec null -aspect 1.78 -c:v mpeg2video -b:v 4650000 -r 29.970 -s 720x480 FILE.mpg
    ffmpeg -i FILE -f ac3  -ar 48000 -vcodec null FILE.ac3
    # Note:
    #  - avoid changing sample rate of audio where possible
    #  - aviod changing resolution in pixels, aspect ratio or bitrate of video where possible
    #  both of these actions can be lossy
    #  I try to keep as close to the original format as possible
    mplex -o FILE.vob FILE.mpg FILE.ac3

EOF
}
if [ "$1" == "-h" ]; then
	usage; exit 0
fi
FILE=${1##*/}
FILE=${FILE%%.*}
if [ "$FILE.vob" == "$1" ]; then
	echo "Input and output should be different files!"
	exit 1
fi
echo avconv -i $1  -f mpeg2video -vcodec copy -acodec null /tmp/$FILE.mpg
echo avconv -i $1  -f ac3 -vcodec null /tmp/$FILE.ac3
echo mplex -f8 -o $FILE.vob /tmp/$FILE.mpg /tmp/$FILE.ac3
