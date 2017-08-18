#!/bin/bash
# Usage
show_help() {
   cat <<EOF

   Usage: ${0##*/} [-hv] [-f OUTPUT] INPUT
   
       -h    display this help and exit.
       -f    output file name. 
       -v    increase verbosity for each -v found.
                                                                                
   Examples:

       ${0##*/} INPUT
          This encodes the INPUT file into a wav file suitable for burning with
          cdrdao. The output wav file is wavdump

EOF
}


VERBOSITY=0
TOP='________________________________________________________________________________'
BOT='________________________________________________________________________________
````````````````````````````````````````````````````````````````````````````````'
MID='++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
DIVIDER=$BOT'
'$TOP

# BEGIN get options
OPTIND=1

while getopts ":hv:f:" opt; do
    case $opt in
		h)
			show_help
			exit 0
			;;
		v)
			VERBOSITY=$(($VERBOSITY+1))
			;;
		f)
			OUTPUT="$OPTARG"
			;;
		
		'?')
			show_help >&2
			exit 1
			;;
		':')
			case $OPTARG in
				f)
					;&
				*)
					show_help >&2
	    			exit 1
					;;
			esac
			;;
    esac
done
shift "$((OPTIND-1))" #Shift off the options and optional --
INPUT="$@"
if [ -z "$INPUT" ]; then show_help; exit 1; fi
echo "$TOP"
echo "Input: $INPUT"
if ! [ -z "$OUTPUT" ]; then
	echo "Output: $OUTPUT"
else echo "Output: audiodump.wav"
fi
###############################################################################
while read line; do
	if [[ $line =~ Duration ]]; then
		DURATION=$(( $( date -u --date="$(echo $line | cut -d':' -f2- | cut -d' ' -f2)" +%s ) - $( date -u --date="0:00:00" +%s ) ))
	elif [[ $line =~ 'Sample Rate' ]]; then
		RATE=$(echo $line | cut -d':' -f2- | cut -d' ' -f2)
	fi
echo $line
done <<EOF
$(soxi "$INPUT")
EOF
################################################################################
: ${MAX_LEN:=4800}      # 80 minute CD...
CDDA_RATE=44100   # CDDA audio...
ARGS="-S -V3 -G "
: ${FILTERS=""}
: ${SILENCE_REMOVED:=false}
: ${SILENCE_DURATION=00:03}
: ${SILENCE_THRESHOLD=-73d}
: ${BURST_DURATION:=0.5}
set -x
if [ "${PRE_PROCESS:-x}" != "x" ]; then
	echo "Pre-processing..."
	TMP=/tmp/${OUTPUT%%.*}-pre.${OUTPUT##*.}
	if [ "$(soxi "$INPUT" 2>&1 1>/dev/null | cut -d':' -f1)" == "soxi FAIL formats" ]; then
		ffmpeg -i $INPUT -f sox - | (sleep 1; sox $ARGS - $TMP $PRE_PROCESS)
	else
		sox $ARGS "$INPUT" "$TMP" $PRE_PROCESS
	fi
	INPUT=$TMP
	DURATION=$(( $( date -u --date="$(soxi "$INPUT" | grep Duration | cut -d':' -f2- | cut -d' ' -f2)" +%s ) - $( date -u --date="0:00:00" +%s ) ))
	RATE=$(soxi "$INPUT" | grep "Sample Rate" | cut -d':' -f2- | cut -d' ' -f2)
	echo "Pre-processing complete. New Duration: $DURATION"
fi
###############################################################################
[ $DURATION ] || while read line; do
	if [[ $line =~ Duration ]]; then
		DURATION=$(( $( date -u --date="$(echo $line | cut -d':' -f2- | cut -d' ' -f2)" +%s ) - $( date -u --date="0:00:00" +%s ) ))
	elif [[ $line =~ 'Sample Rate' ]]; then
		RATE=$(echo $line | cut -d':' -f2- | cut -d' ' -f2)
	fi
echo $line
done <<EOF
$(soxi $INPUT)
EOF
################################################################################
while (( DURATION > MAX_LEN )); do
	if $SILENCE_REMOVED; then
		TEMPO=$(( DURATION / MAX_LEN )).$( printf %02d $(( ( DURATION % MAX_LEN ) * 100 / MAX_LEN + 1)) )
		FILTERS=$FILTERS" tempo $TEMPO"
		echo "$DIVIDER"
		echo "Tempo: $TEMPO"
		break
	else
		echo "$DIVIDER"
		echo "Trying to trim silence rather than increase tempo..."
		TMP=/tmp/${OUTPUT%%.*}-tmp.${OUTPUT##*.}
		if [ -f "$TMP" ]
		then 
			read -p "Intermediate file found! Reuse? (selecting no with overwrite) y/n: " RESPONSE
			if ! [[ $RESPONSE =~ y ]]
			then
				set -x
				sox $ARGS "$INPUT" "$TMP" silence -l 1 ${BURST_DURATION} $SILENCE_THRESHOLD -1 $SILENCE_DURATION $SILENCE_THRESHOLD
				set +x
			fi
		else
			sox $ARGS "$INPUT" "$TMP" silence -l 1 ${BURST_DURATION} $SILENCE_THRESHOLD -1 $SILENCE_DURATION $SILENCE_THRESHOLD
		fi
		rm /tmp/*-pre.wav
		INPUT=$TMP
	        DURATION=$(( $( date -u --date="$(soxi "$INPUT" | grep Duration | cut -d':' -f2- | cut -d' ' -f2)" +%s ) - $( date -u --date="0:00:00" +%s ) ))
		echo "Silence trimmed. New duration: $DURATION"
		SILENCE_REMOVED=true
	fi
done
if (( CHANNELS != 2 )); then
	FILTERS=$FILTERS" channels 2 "
fi
if [ "$RATE" != "$CDDA_RATE" ]; then
	FILTERS=$FILTERS" rate $CDDA_RATE "
fi
echo "Dumping wave file..."
set -x
if [ -f $OUTPUT ]; then
	read -p "Overwrite $OUTPUT? y/n: " RESPONSE
	if ! [[ $RESPONSE =~ y ]]
	then
		exit 1
	fi
fi
sox $ARGS "$INPUT" $PREOUT -t wavpcm -b 16 "$OUTPUT" $FILTERS
set +x
echo "... done!"
	
