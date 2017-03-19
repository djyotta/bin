#!/bin/bash
# Usage
show_help() {
   cat <<EOF

   Usage: ${0##*/} [-hv] [-a ARGS] INPUT
   
       -h    display this help and exit.
       -a    extra arguments to give to cdrdao (write mode).
       -v    increase verbosity for each -v found.
                                                                                
   Examples:

       ${0##*/} INPUT
          This writes the INPUT toc to cd with cd-text (if supplied).

       ${0##*/} -a "--overburn" INPUT
          This writes the INPUT toc to cd with cd-text (if supplied) and supplies
          the --overburn option to 'cdrdao write'.

EOF
}


VERBOSITY=0

ARGS="--driver generic-mmc-raw -v 2 --eject"
TOP='________________________________________________________________________________'
BOT='________________________________________________________________________________
````````````````````````````````````````````````````````````````````````````````'
MID='++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
DIVIDER=$BOT'
'$TOP

# BEGIN get options
OPTIND=1

while getopts ":hva:f:" opt; do
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
		
		a)
			ARGS+=' '"$OPTARG"
			;;
		'?')
			show_help >&2
			exit 1
			;;
		':')
			case $OPTARG in
				a)
					;&
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
cdrdao show-toc $INPUT
################################################################################
echo "$DIVIDER"
################################################################################
echo "Writing to disc..."
cdrdao write $ARGS $INPUT
echo "... done!"
