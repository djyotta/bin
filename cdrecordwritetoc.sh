#!/bin/bash
DIR=$(dirname "${BASH_SOURCE[0]}")
# Usage
die (){
	exit $1
}
show_help() {
   cat <<EOF

   Usage: ${0##*/} [-hv] -t TOC -i IMAGE_DIR

       -t    TOC file to write to first session
       -i    IMAGE_DIR to write as second session
       -h    display this help and exit.
       -v    increase verbosity for each -v found.
                                                                                
   Examples:

       ${0##*/} -t TOC -i IMAGE_DIR
	      Like cdrdaowritecd but uses cdrecord to create a multi-session disc (CD-EXTRA).

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
cleanup(){
	#cdemu unload 0
	rm -rf $WD
}
while getopts ":hvt:i:" opt; do
    case $opt in
		h)
			show_help
			exit 0
			;;
		v)
			VERBOSITY=$(($VERBOSITY+1))
			;;
		t)
			TOC="$OPTARG"
			;;
		
		i)
			IMAGEDIR="$OPTARG"
			;;
		'?')
			show_help >&2
			exit 1
			;;
		':')
			case $OPTARG in
				t)
					;&
				i)
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
trap cleanup EXIT 
echo "$TOP"
################################################################################
WD=$(mktemp -d)
echo "Getting isofs size..."
IMAGE=$WD/${IMAGEDIR/%_img/.img}
mkisofs -J -V Slides -v -v -v -r -o $IMAGE $IMAGEDIR
SECTORS=$(isosize -x $IMAGE | grep --only-matching 'sector count. [0-9]\+' | cut -d':' -f2)
####################################################################
# Capacities of Compact Disc types 
# (90 and 99 minute discs are not standard)
# Type    Sectors Data max. size             Audio max. size    Time
#                     (MB) Approx.  (MiB)                (MB)  (min)
# 8 cm     94,500  193.536        184.570             222.264    21
#         283,500  580.608        553.711             666.792    63
# 650 MB  333,000  681.984        650.391             783.216    74
# 700 MB  360,000  737.280        703.125             846.720    80
# 800 MB  405,000  829.440        791.016             952.560    90
# 900 MB  445,500  912.384        870.117           1,047.816    99
####################################################################
AUDIOFILE=$(grep 'FILE .*\.wav' $TOC | head -n 1 | cut -d' ' -f2 | sed 's/"//g')
AUDIOSECTORS=$(soxi ../$AUDIOFILE | grep --only-matching '[0-9]\+ CDDA sectors' | cut -d' ' -f1)
#https://en.wikipedia.org/wiki/Track_(CD) #???
#http://www.murga-linux.com/puppy/viewtopic.php?t=500 vvvvvvv
#Next step is to check if cdrecord is able to retrieve the following data:
# 1) The first block (sector) number in the first track of the last session
# This must be '0' in our case.

# 2) The next writable address in the unwritten session following the current.
# This should be the number of sectors written in the first
# run + ~ 11400 sectors for about 22MB lead out/in

# For the first additional session this is 11250 sectors lead-out/lead-in
# overhead + 150 sectors for the pre-gap of the first track after the
# lead-in = 11400 sectos.

# For all further session this is 6750 sectors lead-out/lead-in
# overhead + 150 sectors for the pre-gap of the first track after the
# lead-in = 6900 sectors.

# To get this information type:

# cdrecord -msinfo dev=2,0

# The output should be two numbers separated by a comma.

# e.g.: 0,204562

# The first number is (1), the second number is (2).
LEADOUT1=11400 # length of lead in/out (1st session) in sectors
LEADOUT=6900  # length of lead in/out (other sessions) in sectors
EXTRASECTORS=$((${LEADIN1}+AUDIOSECTORS+LEADOUT+SECTORS-360000))
################################################################################
if ((EXTRASECTORS/75 > 0)); then 
	echo "Need $((EXTRASECTORS/75)) seconds extra..."
	exit 1
fi
echo "... done!"
echo "$DIVIDER"
################################################################################
echo "Create FAKE CD with cdemu..."
EMU=$WD/emu
mkdir $EMU
touch $EMU/disc.toc
cdemu unload 0
cdemu create-blank --writer-id=WRITER-TOC --medium-type=cdr80 0 $EMU/disc.toc || die $?
echo "... done!"
echo "$DIVIDER"
echo "Burn to FAKE CD with cdrdao (to write CD-TEXT from TOC)..."
cdrdao write -n --driver generic-mmc-raw -v 2 --eject --device /dev/sr1 $TOC || die $?
echo "... done!"
echo "$DIVIDER"
################################################################################
echo "Reading TOC from FAKE CD with cdrecord (to get cdtext.dat)..."
cdemu unload 0
cdemu load 0 $EMU/disc.toc || die $?
cd $WD
cdrecord -vv -toc dev=/dev/sr1
cd -
cdemu unload 0
echo "... done!"
echo "$DIVIDER"
################################################################################
echo "Burning REAL CD with cdrecord..."
cdrecord dev=/dev/sr0 speed=4 -eject -multi -sao -textfile=$WD/cdtext.dat -audio $EMU/disc-??.wav || die $?
echo "... done!"
echo "$DIVIDER"
################################################################################
echo "Creating data session to follow..."
mkisofs -J -V Slides -v -v -v -r -C $(cdrecord dev=/dev/sr0 -msinfo) -o $IMAGE $IMAGEDIR || die $?
echo "... done!"
echo "$DIVIDER"
################################################################################
echo "Burning data session with cdrecord..."
cdrecord dev=/dev/sr0 speed=8 -v -eject $IMAGE || die $?
echo "... done!"
echo "$BOT"
