#!/bin/sh
error_exit() {
  echo $*
  exit 1
}
help() {
  echo
  echo "usage: $(basename $0) <option> <command> <cmd options>"
  echo
  echo "           -L : screen session logging to screenlog.n"
  exit
}

_cmd=$@

[ $# -le 0 ] && help

sessions=( )
[ -d /var/run/screen/S-$(id -u -n) ] && sessions=( $(ls /var/run/screen/S-$(id -u -n)/ ) )

get_session() {
  _new_sessions=( $(ls /var/run/screen/S-$(id -u -n)/) )
  i=$(expr ${#_new_sessions[*]} - 1)
  while [ 0 -le $i ]; do
    if [ "${sessions[$i]}" != "${_new_sessions[$i]}" ]; then
       echo ${_new_sessions[$i]}
       break
    fi
    i=$(expr $i - 1)
  done
}

while [ 1 ]; do
  [ -f /tmp/S-$(id -u -n).lock ] || break
  sleep 1
done

touch /tmp/S-$(id -u -n).lock
screen -d -m $_cmd
sleep 0.1
screen_session=$(get_session)
rm -f /tmp/S-$(id -u -n).lock

[ -n "$screen_session" ] || exit 1
echo $screen_session
exit 0
