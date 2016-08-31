#!/bin/bash
#
# A simple scriptlet to prepare a file ripped with ./rip.sh for authoring
#
FILE=${1##*/}
FILE=${FILE%%.*}
if [ "$FILE.vob" == "$1" ]; then
	echo "Input and output should be different files!"
	exit 1
fi
echo avconv -i $1  -f mpeg2video -vcodec copy -acodec null /tmp/$FILE.mpg
echo avconv -i $1  -f ac3 -vcodec null -acodec copy /tmp/$FILE.ac3
echo mplex -f8 -o $FILE.vob $FILE.mpg $FILE.ac3
echo dvdauthor -o image --title --video pal --audio pcm --file $FILE.vob
