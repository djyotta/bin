#!/bin/bash
#
# Simple scriptlet to rip video off a dvd
# \1 - start time
# \2 - duration
#
set -x
while getopts ":s:e:o:" opt; do
	case $opt in
		s)
			ss=$OPTARG
			ARGS=$ARGS" -ss $ss"
			start=$ss; start=${start/:/_}; start=${start/./_}
			;;
		e)
			endpos=$OPTARG
			ARGS=$ARGS" -endpos $endpos"
			end=$endpos; end=${end/:/_}; end=${end/./_};
			;;
		o)
			output=$OPTARG
			;;
	esac
done
shift $((OPTIND-1))
		
if [ "${output-x}" == "x" ]; then
	output=${1##*/}
	output=${output%%.*}
fi
PREFIX=${output}
if ! [ "${start-x}" == "x" ]; then
	PREFIX=${PREFIX}_${start}
fi
if ! [ "${end-x}" == "x" ]; then
	PREFIX=${PREFIX}_${end}
fi

# NOTE: we use -oac pcm here as copy doesn't always work! Also, even when copy works, the output is usually not in sync.
echo "mencoder $ARGS -oac pcm -ovc copy  -o ./$PREFIX.avi $1"
