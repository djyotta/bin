#!/bin/bash

HELP="$(printf '%d' 0x68656c70)"
USER=auckland
NOTICE=false
ADMINURL='http://webcast.lcg.org/admin'
USERURL='http://webcast.lcg.org'
COOKIE=$(pwd)/cookie
NEWCOOKIE=false
FINALIZE=false
DOWNLOAD=false
# -t TYPE is one of:
#         BS       Bible Study
#         PM       Afternoon Service
#         AM       Morning Service
#         TEST     Test (won't show in archive)
#    which will save as Bible Study, or as Test.

urlencode() {
    # urlencode <string>
    old_lc_collate=$LC_COLLATE
    LC_COLLATE=C

    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done

    LC_COLLATE=$old_lc_collate
}

die(){
    if [ "$2" ]; then echo "$2" >&2; fi
    if (( $1 == $HELP )); then show_help >&2; fi
    exit $1
}

show_help(){
cat <<EOF

  usage: ${0##*/} [[-u USERNAME] -p PASSWORD]  [-n FILE] [-t TYPE [-d DATE]|[-f]]
    -u     provide the Stream Site  (deafult=$USER)
    -p     provide the PASSWORD
    -n     update notice board. The message is taken from stdin unless FILE is specified
    -t     type of stream.
    -f     finalize stream. Must supply -t
    -d     download an archived stream. Must supply -t
           DATE is like: mm-dd-yy (EST I think)

EOF
}
while getopts ":u:p:n:d:t:fhv" opt; do
    case $opt in
		h)
			show_help
			die 0
			;;
		v)
			VERBOSITY=$((VERBOSITY+1))
			;;
		u)
			USER=$OPTARG
			;;
		p)
            PASS=$OPTARG
            NEWCOOKIE=true
			;;
        f)
            FINALIZE=true
            ;;
        d)
            DOWNLOAD=true
            DATE=$OPTARG
            ;;
        t)
            TYPE=$OPTARG
            ;;
        n)
            NOTICE=true
            NOTICEFILE=$OPTARG
            ;;
		'?')
			die $HELP
			;;
		':')
			case $OPTARG in
				d)
                    ;&
                t)
                    ;&
				p)
                    die $HELP "-$OPTARG requires an argument"
                    ;;
                n)
                    #use stdin
                    ;;

				*)
                    die $HELP "Unrecognised option: -$OPTARG"
					;;
			esac
			;;
		*)
			die $HELP
			;;
	esac
done
if [ "${PASS:-undef}" == "undef" ] && ! [ -f "$COOKIE" ]; then
    die $HELP "Password must be specified!"
fi
if $NEWCOOKIE; then
    curl -c $COOKIE \
         "${ADMINURL}/index.php" \
         -H 'Host: webcast.lcg.org' \
         -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
         -H 'Accept-Language: en-US,en;q=0.5' \
         --compressed \
         -H "Referer: ${ADMINURL}/adminlogin.php" \
         -H 'DNT: 1' \
         -H 'Connection: keep-alive' \
         -H 'Upgrade-Insecure-Requests: 1' \
         --data "site=${USER}&password=${PASS}&login_submitted=login_submitted" | html2text
fi

if $FINALIZE; then
    if ! [ "${TYPE:-undef}" == "undef" ]; then
        curl -b $COOKIE -c $COOKIE \
             "${ADMINURL}/rename.php" \
             -H 'Host: webcast.lcg.org' \
             -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
             -H 'Accept-Language: en-US,en;q=0.5' \
             --compressed \
             -H "Referer: ${ADMINURL}/index.php" \
             -H 'DNT: 1' \
             -H 'Connection: keep-alive' \
             -H 'Upgrade-Insecure-Requests: 1' \
             --data "type=$TYPE" | html2text
    else
        die $HELP "-t must be specified!"
    fi
fi

if $DOWNLOAD; then
    if ! [ "${TYPE:-undef}" == "undef" ] && ! [ "${DATE:-undef}" == "undef" ] && ! [ "${USER:-undef}" == "undef" ]; then
        MERGE=merge.txt
        PLAYLIST=$(curl -b $COOKIE -c $COOKIE \
             "${USERURL}/replay.php" \
             -H 'Accept-Encoding: gzip, deflate' \
             -H 'Accept-Language: en-GB,en-US;q=0.8,en;q=0.6' \
             -H 'Origin: http://webcast.lcg.org' \
             -H 'Upgrade-Insecure-Requests: 1' \
             -H 'Content-Type: application/x-www-form-urlencoded' \
             -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8' \
             -H 'Referer: http://webcast.lcg.org/index.php' \
             -H 'Connection: keep-alive' \
             --data "video=${USER}_${DATE}_${TYPE}.mp4" \
             --compressed | grep 'sourceURL.*playlist.m3u8' | grep -o '[-/0-9A-Za-z\.:_]\+playlist.m3u8')
        wget -q -O - "http:${PLAYLIST}" | while read line ; do
            if [[ "$line" =~ "#" ]]; then 
                continue
            else 
                echo "" > $MERGE
                wget -q -O - "http:${PLAYLIST%/*}/$line" | while read subline ; do
                    if [[ "$subline" =~ "#" ]]; then
                        continue
                    else
                        echo "Downloading fragment: $subline"
                        wget "http:${PLAYLIST%/*}/$subline"
                        echo file "'${subline}'" >> $MERGE
                    fi
                done
            fi
        done
        # join
        ffmpeg -f concat -i $MERGE  -c copy "${USER}_${DATE}_${TYPE}.ts"
    else
        die $HELP "-t, -d and -u must be specified!"
    fi
fi

if $NOTICE; then
    [ "${NOTICEFILE:=-}" == "-" ] && echo "Type a message:"
    html=$(cat ${NOTICEFILE} | sed -e 's/\t\(.*\)$/\<blockquote\>\1\<\/blockquote\>/g' | sed -e 's/^/\<p\>/g')
    data=$(urlencode "$html")
    curl -b $COOKIE -c $COOKIE \
         "${ADMINURL}/update.php" \
         -H 'Host: webcast.lcg.org' \
         -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
         -H 'Accept-Language: en-US,en;q=0.5' \
         --compressed \
         -H "Referer: ${ADMINURL}/index.php" \
         -H 'Connection: keep-alive' \
         -H 'Upgrade-Insecure-Requests: 1' \
         --data "schedule=$data" | html2text
fi
