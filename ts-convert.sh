if [[ "$1" =~ ":" ]]; then
	echo $(($(date -u --date="$1" +%s) - $(date -u --date="00:00:00" +%s) ))
elif (( $1 % 1 == 0 )); then
	date -u --date="@$1" +%H:%M:%S
fi
