#!/bin/bash
#########################################################
# Install Example 
# bash munge_install_uninstall.sh install https://github.com/dun/munge/archive/munge-0.5.13.tar.gz /global/opt/munge
#########################################################
# Uninstall Example 
# bash munge_install_uninstall.sh uninstall
#########################################################

error_exit() {
    echo "$*"
    exit
}

munge_init() {
   prefix=$1
   sysconfdir=$2
   localstatedir=$3
   [ -f /etc/init.d/munge ] && mv /etc/init.d/munge /etc/init.d/munge.orig
   if [ -d /lib/systemd/system ]; then
       echo "[Unit]
Description=Munge service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/etc/init.d/munge start
ExecStop=/etc/init.d/munge stop
ExecReload=-/etc/init.d/munge restart

[Install]
WantedBy=multi-user.target
" > /lib/systemd/system/munge.service
   fi
   cat << EOF > /etc/init.d/munge
#!/bin/sh
###############################################################################
# chkconfig:          - 66 33
# description:        MUNGE Uid 'N' Gid Emporium authentication service
###############################################################################
### BEGIN INIT INFO
# Provides:           munge
# Required-Start:     $local_fs $remote_fs $network $time
# Required-Stop:      $local_fs $remote_fs
# Should-Start:       $named $syslog
# Should-Stop:        $named $syslog
# Default-Start:
# Default-Stop:
# Short-Description:  MUNGE Uid 'N' Gid Emporium authentication service
# Description:        MUNGE (MUNGE Uid 'N' Gid Emporium) is a highly scalable
#                     authentication service for creating and validating
#                     credentials.
### END INIT INFO
###############################################################################
prefix="$prefix"
exec_prefix="$prefix"
sbindir="$prefix/sbin"
sysconfdir="$sysconfdir"
localstatedir="$localstatedir"

SERVICE_NAME="MUNGE"
DAEMON_EXEC="\$sbindir/munged"
PIDFILE="\$localstatedir/run/munge/munged.pid"
USER="munge"
GROUP="munge"
VARRUNDIR="\$localstatedir/run/munge"

. /etc/rc.d/init.d/functions

service_start () {
  printf "Starting \$SERVICE_NAME" "\$DAEMON_NAME"

  if [ -n "\$VARRUNDIR" -a ! -d "\$VARRUNDIR" ]; then
    mkdir -m 755 -p "\$VARRUNDIR"
    [ -n "\$USER" ] && chown "\$USER" "\$VARRUNDIR"
    [ -n "\$GROUP" ] && chgrp "\$GROUP" "\$VARRUNDIR"
  fi
  if service_status >/dev/null 2>&1; then
      STATUS=0
  else
      daemon \${NICE:+"\$NICE"} \${USER:+"--user"} \${USER:+"\$USER"} \
         "\$DAEMON_EXEC" \$DAEMON_ARGS
      STATUS=\$?
  fi
  [ \$STATUS -eq 0 ] && touch "\$RH_LOCK" >/dev/null 2>&1
  return \$STATUS
}

service_stop () {
  printf "Stopping \$SERVICE_NAME" "\$DAEMON_NAME"
  if ! service_status >/dev/null 2>&1; then
      STATUS=0
  else
      killproc \${PIDFILE:+"-p"} \${PIDFILE:+"\$PIDFILE"} \\
        \${SIGTERM_TIMEOUT:+"-d"} \${SIGTERM_TIMEOUT:+"\$SIGTERM_TIMEOUT"} \\
        "\$DAEMON_EXEC"
      STATUS=\$?
  fi
  if [ \$STATUS -eq 0 ]; then
     [ -f "\$RH_LOCK" ] && rm -f "\$RH_LOCK" 
     [ -f "\$PIDFILE" ] && rm -f "\$PIDFILE"
  fi
  return \$STATUS
}

service_restart () {
  if service_status >/dev/null 2>&1; then
    \$0 stop && \$0 start
    return $?
  else
    \$0 start
    return $?
  fi
}


service_reload () {
  [ -z "\$RELOAD" ] && STATUS=3
  printf "Reloading \$SERVICE_NAME" "\$DAEMON_NAME"
  if [ -n "\$RELOAD" ]; then
     killproc \${PIDFILE:+"-p"} \${PIDFILE:+"\$PIDFILE"} "\$DAEMON_EXEC" -HUP
     return \$?
  else
     echo_failure
  fi
}

service_status () {
      status \${PIDFILE:+"-p"} \${PIDFILE:+"\$PIDFILE"} "\$DAEMON_EXEC"
      STATUS=\$?
      return \$STATUS
}

case "\$1" in
  start)
    service_start
    ;;
  stop)
    service_stop
    ;;
  restart)
    service_restart
    ;;
  reload)
    service_reload
    ;;
  status)
    service_status
    ;;
  *)
    echo "Usage: `basename \"\$0\"`" \
      "(start|stop|restart|reload|status)" >&2
    exit 2
    ;;
esac

EOF
   chmod +x /etc/init.d/munge
}


install() {
  opwd=$(pwd)
  munge_file=$1
  munge_install_dir=$2
  sysconfdir="/etc"
  localstatedir="/var"

  [ ! -n "$munge_file" -o ! -n "$munge_install_dir" ] && error_exit "$(basename $0) install <munge file> <munge install dir>

<munge file> : <path>/munge-xxxx.tar.gz  or https://github.com/xxx/munge-xxx.tar.gz"
#https://github.com/dun/munge/archive/munge-0.5.13.tar.gz

  [ -d /tmp/munge ] && rm -fr /tmp/munge
  mkdir -p /tmp/munge
  if echo $munge_file  | grep "^http" >& /dev/null; then
    cd /tmp/munge
    wget $munge_file
    munge_file=/tmp/munge/$(basename $munge_file)
  elif [ ! -f "$munge_file" ]; then
    echo "munge file not found"
    exit
  fi
  cd /tmp/munge
  mkdir 1
  tar zxvf $munge_file -C /tmp/munge/1
  cd /tmp/munge/1/*
  [ -d "$munge_install_dir" ] || mkdir -p ${munge_install_dir}
  ./configure --prefix=$munge_install_dir --enable-static --enable-shared --sysconfdir=$sysconfdir --localstatedir=$localstatedir --runstatedir=$localstatedir/run
  make
  make install
  id munge >& /dev/null || useradd munge
  [ -d $localstatedir/lib/munge ] || mkdir -p $localstatedir/lib/munge 
  chmod 0711 $localstatedir/lib/munge
  chown munge:munge $localstatedir/lib/munge -R
  [ -d $localstatedir/log/munge ] || mkdir -p $localstatedir/log/munge
  chmod 0700 $localstatedir/log/munge
  chown munge:munge $localstatedir/log/munge -R
  [ -d $localstatedir/run/munge ] || mkdir -p $localstatedir/run/munge
  chmod 0755 $localstatedir/run/munge
  chown munge:munge $localstatedir/run/munge -R
  [ -d $sysconfdir/munge ] || mkdir -p $sysconfdir/munge 
  dd if=$([ -c /dev/urandom ] && echo /dev/urandom || echo /dev/random ) bs=1 count=1024 > $sysconfdir/munge/munge.key
  chmod 0700 $sysconfdir/munge -R
  chown munge:munge $sysconfdir/munge -R
  cd ${opwd}
  rm -fr /tmp/munge

  munge_init "$munge_install_dir" "$sysconfdir" "$localstatedir"

  echo "prefix=$prefix
sysconfdir=$sysconfdir
localstatedir=$localstatedir
export PATH=\${PATH}:$munge_install_dir/bin" > /etc/profile.d/munge.sh
  source /etc/profile.d/munge.sh

  systemctl daemon-reload
  /etc/init.d/munge start || error_exit "MUNGE Daemon start fail"

  munge -n
  munge -n | unmunge
  munge -n | ssh localhost unmunge
  remunge
  echo "Munge install done"
}

uninstall() {
  [ -f /etc/profile.d/munge.sh ] && source /etc/profile.d/munge.sh
  if [ -f /lib/systemd/system/munge.service ]; then
     systemctl stop munge
  elif [ -f /etc/init.d/munge ]; then
     /etc/init.d/munge stop
  fi 
  
  sleep 5
  id munge >& /dev/null && userdel munge
  [ -d /etc/munge ] && rm -fr /etc/munge
  [ -d $localstatedir/lib/munge ] && rm -fr $localstatedir/lib/munge
  [ -d $localstatedir/log/munge ] && rm -fr $localstatedir/log/munge
  [ -d $localstatedir/run/munge ] && rm -fr $localstatedir/run/munge
  [ -f /etc/sysconfig/munge ] && rm -f /etc/sysconfig/munge
  [ -f /etc/init.d/munge ] && rm -f /etc/init.d/munge
  [ -f /etc/rc.d/init.d/munge ] && rm -f /etc/rc.d/init.d/munge
  [ -f /etc/profile.d/munge.sh ] && rm -f /etc/profile.d/munge.sh
  [ -f /lib/systemd/system/munge.service ] && rm -f /lib/systemd/system/munge.service
  [ -n "$prefix" -a -d "$prefix" ] && rm -fr $prefix
}

if [ "$1" == "install" ]; then
   shift 1
   install $*
elif [ "$1" == "uninstall" ]; then
   uninstall
else
   echo "$(basename $0) install <munge file> <install path>
or
$(basename $0) uninstall"
fi
