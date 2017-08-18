#!/bin/bash
# Usage
show_help() {
   cat <<EOF

   Usage: ${0##*/} [-hv] -s|b -t TITLE -p SPEAKER INPUT
   
       -h    display this help and exit.
       -v    increase verbosity for each -v found.
       -s|b  sermon or bible study.
       -t    the TITLE of the item.
       -p    the SPEAKER (performer) delivering the item.
       -c    cue information. (ie, STARTTIME ENDTIME).
                                                                                
   Examples:

       ${0##*/} -s -t "Title of Sermon" -p "Dr. Roderick C. Meredith" INPUT
          This encodes creates a toc for INPUT file and CD-TEXT with the
          following information:
              TITLE="Title of Sermon"
              PERFORMER="Dr. Roderick C. Meredith"

EOF
}


VERBOSITY=0

TOP='________________________________________________________________________________'
BOT='________________________________________________________________________________
````````````````````````````````````````````````````````````````````````````````'
MID='++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
DIVIDER=$BOT'
'$TOP

PERFORMER=""
BIBLESTUDY=false
SERMON=false
CUE="0"

# BEGIN get options
OPTIND=1

while getopts ":hvsbt:p:c:" opt; do
    case $opt in
		h)
			show_help
			exit 0
			;;
		v)
			VERBOSITY=$(($VERBOSITY+1))
			;;
		s)
			if $BIBLESTUDY; then show_help; exit 1; fi
			SERMON=true;
			;;
		
		b)
			if $SERMON; then show_help; exit 1; fi
			BIBLESTUDY=true;
			;;
		t)
			TITLE="$OPTARG"
			;;
		p)
			PERFORMER="$OPTARG"
			;;
		c)
			CUE="$OPTARG"
			;;
		'?')
			show_help >&2
			exit 1
			;;
		':')
			case $OPTARG in
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
if ! DATESTAMP="$(echo $INPUT | cut -d'_' -f1)"\
	|| ! YEAR="$(echo $DATESTAMP | head -c4)"\
	|| ! MONTH="$(echo $DATESTAMP | head -c6 | tail -c+5)"\
	|| ! DATE="$(echo $DATESTAMP | tail -c+7)"
then
	echo "The input filename does not have the correct name format!"
	show_help
	exit 1
fi
OUTPUT="$(echo ${INPUT%.*} | cut -d'-' -f1).toc"
if [ "$OUTPUT" = ".toc" ]; then
	echo "The input filename does not have the correct name format!"
	show_help
	exit 1
fi
if [ -z "$PERFORMER" ]; then show_help; exit 1; fi
if ! $BIBLESTUDY && ! $SERMON; then show_help;exit 1;fi
DURATION=$(~/git/bin/ts-convert.sh $(soxi $INPUT | awk -e '/Duration/ { print $3 }'))
TRACKS=$((DURATION/5/60))
if $((DURATION%(5*60) > 150)); then
	TRACKS=$(TRACKS-1)
fi

echo "$TOP"
echo "Input: $INPUT"
echo "Output: $OUTPUT"
################################################################################
echo "$DIVIDER"
################################################################################
echo "Writing toc file..."
max_index=$TRACKS
if (( $VERBOSITY > 1 )); then
	set -v
fi
cat > $OUTPUT <<EOF
CD_DA

CD_TEXT {
  LANGUAGE_MAP {
    0 : EN
  }

  LANGUAGE 0 {
    TITLE "`if $BIBLESTUDY; then echo "Bible Study"; elif $SERMON; then echo "Sermon";fi` $DATE-$MONTH-$YEAR"
    PERFORMER "Living Church of God"
  }
}

`index=1; while (( $index < $max_index )); do 
echo -e "TRACK AUDIO
CD_TEXT {
  LANGUAGE 0 {
    TITLE \"$TITLE $index/$max_index\"
    PERFORMER \"$PERFORMER\"
  }
}
FILE \"$INPUT\" $((($index-1)*5)):00:00 05:00:00"
index=$(($index+1))
done`
TRACK AUDIO
CD_TEXT {
  LANGUAGE 0 {
    TITLE "$TITLE $max_index/$max_index"
    PERFORMER "$PERFORMER"
  }
}
FILE "$INPUT" $((($max_index-1)*5)):00:00                  
EOF
if (( $VERBOSITY > 0 )); then 
  cat $OUTPUT
fi
set +v
echo "... done!"
