#!/bin/bash

error_exit() {
    echo "$*"
    exit
}

slurm_conf() {
   slurm_dir=$1
   sysconfdir=$2
   localstatedir=$3
   cluster_name=$4
   controlmachine=$5
   device=$6
   user=$7
   epilog=$8
   node_name=$9
   pam=$10
   [ -n "$controlmachine" ] || controlmachine=$(hostname)
   [ -n "$user" ] || user=root
   [ -d $sysconfdir ] || mkdir -p $sysconfdir
   cat << EOF > $sysconfdir/slurm.conf
ClusterName=$cluster_name
ControlMachine=$controlmachine
$(if [ -n "$device" -a -d /sys/class/net/$device ]; then 
  control_ip=$(ifconfig $device | grep "inet " | awk '{print $2}')
  echo "ControlAddr=$control_ip"
 fi
)
#BackupController=
#BackupAddr=
#
SlurmUser=$user
SlurmctldPort=6817
SlurmdPort=6818
AuthType=auth/munge
#JobCredentialPrivateKey=
#JobCredentialPublicCertificate=
StateSaveLocation=$localstatedir/spool/slurm/ctld
SlurmdSpoolDir=$localstatedir/spool/slurm/d
SwitchType=switch/none
MpiDefault=none
SlurmctldPidFile=$localstatedir/run/slurmctld.pid
SlurmdPidFile=$localstatedir/run/slurmd.pid
ProctrackType=proctrack/pgid
#PluginDir=
CacheGroups=0
ReturnToService=0
#FirstJobId=
#MaxJobCount=
#PlugStackConfig=
#PropagatePrioProcess=
#PropagateResourceLimits=
#PropagateResourceLimitsExcept=
#Prolog=
#Epilog=
#SrunProlog=
#SrunEpilog=
#TaskProlog=
#TaskEpilog=
#TaskPlugin=
#TrackWCKey=no
#TreeWidth=50
#TmpFS=
UsePAM=$([ "$pam" == "pam" ] && echo 1 || echo 0)
#
# TIMERS
SlurmctldTimeout=300
SlurmdTimeout=300
InactiveLimit=0
MinJobAge=300
KillWait=30
Waittime=0
#
# SCHEDULING
SchedulerType=sched/backfill
#SchedulerAuth=
SelectType=select/linear
FastSchedule=1
#PriorityType=priority/multifactor
#PriorityDecayHalfLife=14-0
#PriorityUsageResetPeriod=14-0
#PriorityWeightFairshare=100000
#PriorityWeightAge=1000
#PriorityWeightPartition=10000
#PriorityWeightJobSize=1000
#PriorityMaxAge=1-0
#
# LOGGING
SlurmctldDebug=3
SlurmctldLogFile=$localstatedir/log/slurmctld.log
SlurmdDebug=3
SlurmdLogFile=$localstatedir/log/slurmd.log
JobCompType=jobcomp/none
#JobCompLoc=
#
# ACCOUNTING
#JobAcctGatherType=jobacct_gather/linux
#JobAcctGatherFrequency=30
#
#AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageType=accounting_storage/filetxt
AccountingStorageLoc=$slurm_dir/accounting/slurm_job_accounting.txt
#AccountingStorageHost=
#AccountingStorageLoc=
#AccountingStoragePass=
#AccountingStorageUser=
#
# COMPUTE NODES
#PropagateResourceLimitsExcept=MEMLOCK
$([ -n "$epilog" ] && echo "Epilog=$epilog")
#NodeName=$node_name Sockets=1 CoresPerSocket=1 ThreadsPerCore=1 State=UNKNOWN
NodeName=$node_name Procs=1 State=UNKNOWN
PartitionName=test.q Nodes=$node_name Default=YES MaxTime=INFINITE State=UP
ReturnToService=1

EOF
}


install() {
  opwd=$(pwd)
  slurm_file=$1
  slurm_install_dir=$2
  munge_dir=$3
  cluster_name=$4
  node_name=$5
  device=$6
  pam=$7
  epilog=$8
  sysconfdir="/etc/slurm"
  localstatedir="/var"

  [ ! -n "$slurm_file" -o ! -n "$slurm_install_dir" -o ! -n "$munge_dir" -o ! -n "$cluster_name" -o ! -n "$node_name" ] && error_exit "$(basename $0) install <slurm file> <slurm install dir> <munge dir> <cluster name> <node name> [<slurm net device name>] [pam] [<epilog file>]

<slurm file>              : <path>/slurm-xxxx.tar.bz2  or https://download.schedmd.com/slurm/slurm-17.11.4.tar.bz2
<cluster name>            : SLURM cluster name
<node name>               : SLURM nodes (ex: test[1-3])
[<slurm net device name>] : SLURM communication network device name
[pam]                     : use pam then type pam
[<epilog file>]           : cleanup epilog file
"
  grep " $(hostname) " /etc/hosts >& /dev/null || error_exit "$(hostname) not found in /etc/hosts file"
  if [ -n "$device" ]; then
     [ -d /sys/class/net/$device ] || error_exit "$device not found"
  fi
  if [ -n "$epilog" ]; then
     [ -f $epilog ] || error_exit "$epilog file not found"
  fi
  [ -d $munge_dir ] || error_exit "munge directory not found"
  if ! munge -n >& /dev/null; then
      if [ -f /etc/init.d/munge ]; then
         /etc/init.d/munge start 
         sleep 2
         /etc/init.d/munge status || error_exit "MUNGE is not ready"
      else
         systemctl start munge
         sleep 2
         systemctl status munge || error_exit "MUNGE is not ready"
      fi
  fi
  [ -d $sysconfdir ] || mkdir -p $sysconfdir

  [ -d /tmp/slurm ] && rm -fr /tmp/slurm
  mkdir -p /tmp/slurm
  if echo $slurm_file  | grep "^http" >& /dev/null; then
    cd /tmp/slurm
    wget $slurm_file
    slurm_file=/tmp/slurm/$(basename $slurm_file)
  elif [ ! -f "$slurm_file" ]; then
    echo "slurm file not found"
    exit
  fi
  cd /tmp/slurm
  mkdir 1
  tar jxvf $slurm_file -C /tmp/slurm/1
  cd /tmp/slurm/1/*
  [ -d "$slurm_install_dir" ] || mkdir -p ${slurm_install_dir}
  ./configure --prefix=$slurm_install_dir --enable-static --enable-shared --sysconfdir=$sysconfdir --localstatedir=$localstatedir --runstatedir=$localstatedir/run --with-munge=$munge_dir $([ "$pam" == "pam" ] && echo "--enable-pam")
  make -j 6
  make install
  cp -a contribs/sjstat $slurm_install_dir/bin
  if [ ! -d $slurm_dir/accounting ]; then
     mkdir -p $slurm_dir/accounting
     chown slurm:slurm $slurm_dir/accounting
  fi
  if [ -d /lib/systemd/system ]; then
     cp -a etc/slurmctld.service /lib/systemd/system/slurmctld.service
     cp -a etc/slurmd.service /lib/systemd/system/slurmd.service
     cp -a etc/slurmdbd.service /lib/systemd/system/slurmdbd.service
     systemctl daemon-reload
  else
     cp -a etc/init.d.slurm /etc/init.d/slurm
     cp -a etc/init.d.slurmdbd /etc/init.d/slurmdbd
     chmod +x /etc/init.d/slurm
     chmod +x /etc/init.d/slurmdbd
  fi
  
  if [ -f etc/slurm.epilog.clean ]; then
     mkdir -p $slurm_install_dir/epilog
     cp -a etc/slurm.epilog.clean  $slurm_install_dir/epilog/slurm.epilog.clean
     chmod +x $slurm_install_dir/epilog/slurm.epilog.clean
     cfg_epilog_file=$slurm_install_dir/epilog/slurm.epilog.clean
  fi
  id slurm >& /dev/null || useradd --system slurm
  openssl genrsa -out $sysconfdir/slurm.key 1024
  openssl rsa -in $sysconfdir/slurm.key -pubout -out $sysconfdir/slurm.cert
  echo "#
# Example /etc/sysconfig/slurm
#
# Increase the memlock limit so that user tasks can get
# unlimited memlock
ulimit -l unlimited
#
# Increase the open file limit
ulimit -n 8192
#
# Memlocks the slurmd process's memory so that if a node
# starts swapping, the slurmd will continue to respond
SLURMD_OPTIONS=\"-M\"" > /etc/sysconfig/slurm

  echo "SLURMCTLD_OPTIONS=\" -v -L $localstatedir/log/slurmctld.log -f $sysconfdir/slurm.conf\"" > /etc/sysconfig/slurmctld
  [ -d /var/spool/slurm ] && rm -fr /var/spool/slurm
  mkdir -p /var/spool/slurm
  chown slurm:slurm /var/spool/slurm
  [ -f /var/log/slurm_jobacct.log ] && rm -f /var/log/slurm_jobacct.log
  touch /var/log/slurm_jobacct.log
  chown slurm:slurm /var/log/slurm_jobacct.log

  echo "prefix=$slurm_install_dir
sysconfdir=$sysconfdir
localstatedir=$localstatedir
LD_LIBRARY_PATH=$slurm_install_dir/lib/slurm
LD_RUN_PATH=$slurm_install_dir/lib/slurm
PATH=\${PATH}:$slurm_install_dir/bin
export PATH LD_LIBRARY_PATH LD_RUN_PATH" > /etc/profile.d/slurm.sh

  source /etc/profile.d/slurm.sh
  cd ${opwd}
  rm -fr /tmp/slurm

  slurm_conf "$slurm_install_dir" "$sysconfdir" "$localstatedir" "$cluster_name" "" "$device" "slurm" "$cfg_epilog_file" "$node_name" "$pam"

  systemctl start slurmctld
  sleep 5
  systemctl start slurmd
  sleep 5
  sinfo
  sleep 5
  srun -n 1 hostname
  srun -N 1 hostname
  srun -p test -N 1 hostname
  cat << EOF > /global/testq
#!/bin/sh
#SBATCH --time=1
#SBATCH --partition=test.q
/bin/hostname
sleep 10
srun -l /bin/hostname
sleep 10
srun -l /bin/pwd
EOF
  sbatch -n1 -o /global/testq.stdout /global/testq 
  sleep 2
  sjstat
  sleep 2
  for (( ii=0; ii<100; ii++)); do
     [ "$(sjstat  | awk '{if($4=="test" && $5=="R") printf "Run"}')" == "Run" ] || break
     echo "Wait running job..."
     sleep 5
  done
  sjstat
  sleep 5
  echo "testq output: "
  cat /global/testq.stdout
  sleep 3
  rm -f /global/testq.stdout /global/testq

  echo "Slurm install done"
  echo "reference for config file : https://slurm.schedmd.com/configurator.html"
}

uninstall() {
  echo "Plase backup your important file first"
  echo -n "Are you sure uninstall SLURM (y/[n]) ? "
  read xy
  if [ "$xy" == "y" -o "$xy" == "Y" ]; then
  [ -f /etc/profile.d/slurm.sh ] && source /etc/profile.d/slurm.sh
  if [ -f /lib/systemd/system/slurmctld.service ]; then
     systemctl stop slurmctld
  fi
  if [ -f /lib/systemd/system/slurmd.service ]; then
     systemctl stop slurmd
  fi 
  
  sleep 5
  id slurm >& /dev/null && userdel slurm
  [ -d /etc/slurm ] && rm -fr /etc/slurm
  [ -d $localstatedir/spool/slurm ] && rm -fr $localstatedir/spool/slurm
  [ -f $localstatedir/log/slurmctld.log ] && rm -f $localstatedir/log/slurmctld.log
  [ -f $localstatedir/log/slurm_jobacct.log ] && rm -f $localstatedir/log/slurm_jobacct.log
  [ -f $localstatedir/log/slurmd.log ] && rm -f $localstatedir/log/slurmd.log
  [ -f /etc/profile.d/slurm.sh ] && rm -f /etc/profile.d/slurm.sh
  [ -f /lib/systemd/system/slurmctld.service ] && rm -f /lib/systemd/system/slurmctld.service
  [ -f /lib/systemd/system/slurmdbd.service ] && rm -f /lib/systemd/system/slurmdbd.service
  [ -f /lib/systemd/system/slurmd.service ] && rm -f /lib/systemd/system/slurmd.service
  [ -n "$prefix" -a -d "$prefix" ] && rm -fr $prefix
  echo "Uninstall done"
  fi
}

if [ "$1" == "install" ]; then
   shift 1
   install $*
elif [ "$1" == "uninstall" ]; then
   uninstall
else
   echo "$(basename $0) install 
or
$(basename $0) uninstall"
fi
