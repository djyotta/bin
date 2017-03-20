#!/bin/bash

HELP="$(printf '%d' 0x68656c70)"
USER=auckland
NOTICE=false
URL='http://webcast.lcg.org/admin'
COOKIE=$(pwd)/cookie
NEWCOOKIE=false

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

  usage: ${0##*/} [[-u USERNAME] -p PASSWORD]  [-f [NAME]] [-n [FILE]]
    -u     provide the Stream Site  (deafult=$USER)
    -p     provide the admin PASSWORD
    -f     finalize stream as type NAME. If NAME not provided, stream will be finalized as a "TEST" stream.
    -n     update notice board. The message is taken from stdin unless FILE is specified

  note: if no password is provided, the existing cookie will be used

EOF
}
while getopts ":u:p:n:f:hv" opt; do
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
            NAME=$OPTARG
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
				p)
                    die $HELP "-$OPTARG requires an argument"
                    ;;
				f)
                    NAME="TEST"
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
         "${URL}/index.php" \
         -H 'Host: webcast.lcg.org' \
         -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
         -H 'Accept-Language: en-US,en;q=0.5' \
         --compressed \
         -H "Referer: $URL/adminlogin.php" \
         -H 'DNT: 1' \
         -H 'Connection: keep-alive' \
         -H 'Upgrade-Insecure-Requests: 1' \
         --data "site=$USER&password=$PASS&login_submitted=login_submitted" | html2text
fi

if ! [ "${NAME:-undef}" == "undef" ]; then
    curl -b $COOKIE -c $COOKIE \
         "${URL}/rename.php" \
         -H 'Host: webcast.lcg.org' \
         -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
         -H 'Accept-Language: en-US,en;q=0.5' \
         --compressed \
         -H "Referer: $URL/index.php" \
         -H 'DNT: 1' \
         -H 'Connection: keep-alive' \
         -H 'Upgrade-Insecure-Requests: 1' \
         --data 'type=$NAME' | html2text
fi

if $NOTICE; then
    [ "${NOTICEFILE:=-}" == "-" ] && echo "Type a message:"
    html=$(cat ${NOTICEFILE} | sed -e 's/\t\(.*\)$/\<blockquote\>\1\<\/blockquote\>/g' | sed -e 's/^/\<p\>/g')
    data=$(urlencode "$html")
    curl -b $COOKIE -c $COOKIE \
         "${URL}/update.php" \
         -H 'Host: webcast.lcg.org' \
         -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
         -H 'Accept-Language: en-US,en;q=0.5' \
         --compressed \
         -H "Referer: $URL/index.php" \
         -H 'Connection: keep-alive' \
         -H 'Upgrade-Insecure-Requests: 1' \
         --data "schedule=$data" | html2text
fi
