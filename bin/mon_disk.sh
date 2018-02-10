#!/bin/sh
# Version : 0.3.51
# Kage  2012-02-24   add replace function, add other options
# Kage  2012-02-24   add md & 3ware
# Kage  2013-08-20   update Megaraid option
# Kage  2013-09-27   update Areca function

MegaRaid_CMD=/usr/local/mon_disk/MegaRaid/CmdTool2
_3Ware_CMD=/usr/local/mon_disk/3ware/tw_cli
_areca_CMD=/usr/local/mon_disk/areca/cli64

error_exit() {
  echo "$*"
  exit
}

help() {
  echo "
  $(basename $0) [ <option>  ]

  none                     : show simple information
  -v ( --verbose)          : show detail information
  --version                : show version
  -h ( --help )            : help
  --threshold   <value>    : checking disk partition usage ( default 85 %)
  -t ( --time ) <value>    : checking period time ( default 30 sec )
  -l ( --loop ) <value>    : loop (default 1)
  -d ( --daemon )          : daemon mode
    -e ( --email ) <userid1@user.domain> [<userid2@user.domain> ...]
                           : if it found any issue then send email to userid@user.domain
                             it need email environment ( sendmail / postfix / etc )

  ----------------------------------------------------------------------------------
  * Additional MegaRaid Controller function. *
  -r ( --replace )         : replace problem HDD
  -rp                      : show rebuild progress (stop : control + c)
  -s                       : make a alarm silence

  ----------------------------------------------------------------------------------
  * Additional NetAPP Storage function. *
  -ip XXX.XXX.XXX.XXX      : outbound IP address of NetAPP Storage
  "
  exit
}


mode=""
argv=( $* )
i=0
while [  $(( ${#argv[*]} -1 )) -ge $i ]; do
    if [ "${argv[$i]}" == "-d" -o "${argv[$i]}" == "--daemon" ]; then
       mode=d
    elif [ "${argv[$i]}" == "-v" -o "${argv[$i]}" == "--verbose" ]; then
       [ "$mode" == "d" ] || mode=v
    elif [ "${argv[$i]}" == "-r" -o "${argv[$i]}" == "--replace" ]; then
       if [ "$mode" != "d" ]; then
         replace=r
         mode=v
       fi
    elif [ "${argv[$i]}" == "-h" -o "${argv[$i]}" == "--help" ]; then
       help
    elif [ "${argv[$i]}" == "-rp" ]; then
       progress=p
    elif [ "${argv[$i]}" == "-s" ]; then
       $MegaRaid_CMD -AdpSetProp -AlarmSilence -aALL
    elif [ "${argv[$i]}" == "--version" ]; then
       grep "^# Version :" $0 | awk -F: '{print $2}'
       exit
    elif [ "${argv[$i]}" == "-t" -o "${argv[$i]}" == "--time" ]; then
       sleep=${argv[$(( $i + 1 ))]}
       i=$(($i+1))
    elif [ "${argv[$i]}" == "-e" -o "${argv[$i]}" == "--email" ]; then
       for (( i=$(($i+1)) ; $i <= $(( ${#argv[*]} -1 )) ; i=$(($i+1)) )); do
           if echo ${argv[$(( $i ))]} | grep "^-" ; then
               break
           else
               email="$email ${argv[$i]}"
           fi
       done
    elif [ "${argv[$i]}" == "-l" -o "${argv[$i]}" == "--loop" ]; then
       loop=${argv[$(( $i + 1 ))]}
       i=$(($i+1))
    elif [ "${argv[$i]}" == "-ip" ]; then
       netapp_ip=${argv[$(( $i + 1 ))]}
       i=$(($i+1))
    elif [ "${argv[$i]}" == "--threshold" ]; then
       threshold=${argv[$(( $i + 1 ))]}
       i=$(($i+1))
    fi
    i=$(($i+1))
done

[ -n "$sleep" ] || sleep=30
[ -n "$loop" ] || loop=1
[ -n "$threshold" ] || threshold=85

kprint() {
   if [ "$1" == "-n" ]; then
	  skip=on
      shift 1
   fi
   printf " %-30s " "$1"
   if [ -n "$2" ]; then
     printf ":"
     printf "\t %-s" "$(echo $2 | sed "s/^ //g")"
   fi
   [ "$kip" == "on" ] || printf "\n"
}


_megaraid(){
   local mode _FAIL_DISKS _CMD_RAID _RAID_VD _RAID_PD _RAID_TAPD chk VD_NUM _ADP
   mode=$1
   _CMD_RAID=$MegaRaid_CMD
   if [ -f $_CMD_RAID ]; then
      _ADP=$($_CMD_RAID -PDGetNum -aALL | grep "Number of Physical" | awk '{print $7}' | sed "s/://g")
      for adp_num in $_ADP; do
        _RAID_VD=$($_CMD_RAID -LDGetNum -a$adp_num |grep "Number of Virtual" | awk -F: '{print $2}' | sed "s/ //g")
        _RAID_TAPD=0
        for N in $(seq 1 $_RAID_VD); do
           _RAID_LD_STATE[$N]=$($_CMD_RAID  -LDInfo -L$(($N-1)) -a$adp_num |grep -w "^State:" | awk -F: '{print $2}' | sed "s/ //g")
           if [ "$mode" == "d" ]; then
               if [ "${_RAID_LD_STATE[$N]}" != "Optimal" ]; then
                  logger "$(basename $0): MagaRaid[a$adp_num]: L$(($N - 1)) State : ${_RAID_LD_STATE[$N]}"
                  echo "$(basename $0): MagaRaid[a$adp_num]: L$(($N - 1)) State : ${_RAID_LD_STATE[$N]}" >> /tmp/raid.email
               fi
           else
               _RAID_PD=$($_CMD_RAID -PDGetNum -a$adp_num |grep "Number of Physical" | awk -F: '{print $2}' | sed "s/ //g")
               _RAID_FW=$($_CMD_RAID -AdpAllInfo -a$adp_num | grep "^FW Version" | awk -F: '{print $2}' | sed "s/ //g")
               _RAID_RAM_SIZE=$($_CMD_RAID -AdpAllInfo -a$adp_num | grep "^Memory Size" | awk -F: '{print $2}' | sed "s/ //g")
               _RAID_AUTO=$($_CMD_RAID -AdpAllInfo -a$adp_num | grep "^Auto Rebuild" | awk -F: '{print $2}' | sed "s/ //g")
               _RAID_SN=$($_CMD_RAID -AdpAllInfo -a$adp_num | grep "^Serial No" | awk -F: '{print $2}' | sed "s/ //g")
               _RAID_PNAME=$($_CMD_RAID -AdpAllInfo -a$adp_num | grep "^Product Name" | awk -F: '{print $2}' | sed "s/^ //g")
#               _RAID_CACHED_IO=$($_CMD_RAID -AdpAllInfo -a$adp_num | grep "^Cached IO" | awk -F: '{print $2}' | sed "s/^ //g")
               _RAID_BBU=$($_CMD_RAID -AdpBbuCmd -GetBbuStatus -a$adp_num | grep "^BatteryType:" | awk -F: '{print $2}' | sed "s/^ //g")
               _RAID_BBU_REPLACE=$($_CMD_RAID -AdpBbuCmd -GetBbuStatus -a$adp_num | grep "Battery Replacement required" | awk -F: '{print $2}' | sed "s/^ //g")
               _RAID_BBU_CHARGE=$($_CMD_RAID -AdpBbuCmd -GetBbuStatus -a$adp_num | grep "^Relative State of Charge" | awk -F: '{print $2}' | sed "s/^ //g")
               _RAID_APD=$( $_CMD_RAID -LDInfo -L$(( $_RAID_VD - $N )) -a$adp_num | grep "Number Of Drives" | awk -F: '{print $2}' )
               _RAID_TAPD=$(( $_RAID_APD + $_RAID_TAPD ))
               _RAID_VD_LEVEL[$N]="$($_CMD_RAID  -LDInfo -L$(($N-1)) -a$adp_num |grep "RAID Level" | awk '{print $3}' | awk -F- '{print $2}'| sed 's/,//g')"
               _RAID_VD_SIZE[$N]="$($_CMD_RAID  -LDInfo -L$(($N-1)) -a$adp_num |grep "^Size" | awk -F: '{print $2}')"
               _RAID_VD_ND[$N]="$($_CMD_RAID  -LDInfo -L$(($N-1)) -a$adp_num |grep "^Number Of Drives" | awk -F: '{print $2}')"
               _RAID_VD_DISK_CACHE[$N]="$($_CMD_RAID  -LDInfo -L$(($N-1)) -a$adp_num |grep "^Disk Cache Policy" | awk -F: '{print $2}' | sed "s/ //g")"
               _RAID_VD_CUR_CACHE[$N]="$($_CMD_RAID  -LDInfo -L$(($N-1)) -a$adp_num |grep "^Current Cache Policy" | awk -F: '{print $2}' | sed "s/^ //g")"
               _RAID_VD_CONSIS[$N]="$($_CMD_RAID  -LDInfo -L$(($N-1)) -a$adp_num |grep -w "Consistency")"
               _RAW_SIZE[$N]=$($_CMD_RAID -LDPDInfo  -a$adp_num | while read line ; do
                    if echo $line | grep "^Virtual Disk:" > /dev/null ; then
                         VD_NUM=$(echo $line | awk -F: '{print $2}' | awk '{print $1}')
                    fi

                    if [ "$VD_NUM" == "$(($N-1))" ]; then
                         if echo $line | grep "^PD:" | grep "Information$" | grep 0 >& /dev/null; then
                             chk=1
                         fi

                         if [ "$chk" == "1" ]; then
                             if echo $line | grep "^Raw Size:">& /dev/null; then
                                  echo $(echo $line | grep "^Raw Size:" | awk -F: '{print $2}' | awk '{printf "%s %s",$1,$2}')
                                  break
                             fi
                         fi
                    fi
               done)
           fi
        done

        _FAIL_DISKS="$( echo $($_CMD_RAID -PDList -aALL | while read line; do  if echo $line |grep "^Enclosure Device ID:" >& /dev/null ; then  e=$(echo $line | awk -F: '{print $2}' | sed "s/ //g"); else if echo $line |grep "^Slot Number:" >& /dev/null ; then  s=$(echo $line | awk -F: '{print $2}' | sed "s/ //g"); fi; if echo $line | grep "^Firmware state:" >& /dev/null; then state=$(echo $line | awk -F: '{print $2}' | awk -F, '{print $1}' | sed "s/ //g");  if [ "$state" != "Online" -a "$state" != "Hotspare" ]; then echo "E$e:S$s($state)"; fi ; fi; fi; done ) )"

        if [ "$mode" == "d" ]; then
          if [ -n "$_FAIL_DISKS" ]; then
             logger "$(basename $0): MegaRaid[a$adp_num]: Issued Disk's Enc & Slot numbers : $_FAIL_DISKS"
             echo "$(basename $0): MegaRaid[a$adp_num]: Issued Disk's Enc & Slot numbers : $_FAIL_DISKS" >> /tmp/raid.email
          fi
          if [ -f /tmp/raid.email ]; then
             echo  >> /tmp/raid.email
             echo "Checking time : $(date)" >> /tmp/raid.email
             echo "monitoring path : $0" >> /tmp/raid.email
             echo "help  : $(basename $0) -h" >> /tmp/raid.email
             for mail in $email ; do
                mail -s $(hostname)_disk_information $mail < /tmp/raid.email
             done
             rm -f /tmp/raid.email
          fi
        else
          [ -n "$_FAIL_DISKS" ] || _FAIL_DISKS=None
          if [ "$mode" == "v" ]; then
              kprint "   Product Name[$adp_num]" "$_RAID_PNAME"
              kprint "   Serial Number[$adp_num]" "$_RAID_SN"
              kprint "   FW Version[$adp_num]" "$_RAID_FW"
              kprint "   Memory size[$adp_num]" "$_RAID_RAM_SIZE"
              kprint "   Auto rebuild[$adp_num]" "$_RAID_AUTO"
              kprint "   Battery Type[$adp_num]" "$_RAID_BBU"
              kprint "   Battery Replacement Req.[$adp_num]" "$_RAID_BBU_REPLACE"
              kprint "   Battery Charge[$adp_num]" "$_RAID_BBU_CHARGE"
              kprint "   Physical Drives[$adp_num]" "$_RAID_PD"
              _RAID_NFD=$(( $_RAID_PD - $_RAID_TAPD ))
              kprint "   Free Physical Drives[$adp_num]" "$_RAID_NFD"
              kprint "   Virtual Drives[$adp_num]" "$_RAID_VD"
          fi
          for N in $(seq 1 $_RAID_VD); do
              if [ "$mode" == "v" ]; then
                  kprint "    - L$(($N - 1)) Raid Level" "${_RAID_VD_LEVEL[$N]}"
                  kprint "    - L$(($N - 1)) Volume Size" "${_RAID_VD_SIZE[$N]}"
                  kprint "    - L$(($N - 1)) # of Physical Disk" "${_RAID_VD_ND[$N]}"
                  kprint "    - L$(($N - 1)) Physical Disk Size" "${_RAW_SIZE[$N]}"
                  kprint "    - L$(($N - 1)) Current Cache" "${_RAID_VD_CUR_CACHE[$N]}"
                  kprint "    - L$(($N - 1)) Disk Cache" "${_RAID_VD_DISK_CACHE[$N]}"
              fi
              kprint "    - L$(($N - 1)) State" "${_RAID_LD_STATE[$N]} $([ "${_RAID_LD_STATE[$N]}" == "Optimal" ] && echo "(OK)" )"
              if [ "$mode" == "v" ]; then
                  [ -n "${_RAID_VD_CONSIS[$N]}" ] && kprint "    -L$(($N - 1)) Consistency" "Yes (Check please for Disk speed)"
              fi
          done
          if [ "$mode" == "v" ]; then
              kprint "    - Issued Disk's [E#:S#]s" "$_FAIL_DISKS"
          fi
        fi
        echo
      done
   fi
}

_megaraid_replace() {
  local FAIL_DISKS _CMD_RAID
   _CMD_RAID=$MegaRaid_CMD
  FAIL_DISKS="$( echo $($_CMD_RAID -PDList -aALL | while read line; do  if echo $line | grep "^Adapter" >/dev/null; then a=$(echo $line | awk '{print $2}' | sed "s/\#//g"); fi; if echo $line |grep "^Enclosure Device ID:" >& /dev/null ; then  e=$(echo $line | awk -F: '{print $2}' | sed "s/ //g"); else if echo $line |grep "^Slot Number:" >& /dev/null ; then  s=$(echo $line | awk -F: '{print $2}' | sed "s/ //g"); fi; if echo $line | grep "^Firmware state:" >& /dev/null; then state=$(echo $line | awk -F: '{print $2}' | awk -F, '{print $1}' | sed "s/ //g");  if [ "$state" != "Online" ]; then echo "$a:$e:$s"; fi ; fi; fi; done) )"


  for pdoff in $FAIL_DISKS; do
    raid=( $(echo $pdoff | sed "s/:/ /g" ) )
    adp=${raid[0]}
    phy="${raid[1]}:${raid[2]}"

    echo
    echo
    echo -n "Disk of Adapter:$adp,  Enclosure:${raid[1]}, Slot:${raid[2]} is correct [Y/n]? "
    read y
    [ -n "$y" ] || y=y
    if [ "$y" != "y" -a "$y" != "Y" ]; then
        echo "Bye~"
        exit
    fi

    $_CMD_RAID -PDOffline -PhysDrv [$phy] -a$adp
    sleep 2
    $_CMD_RAID -PDMarkMissing -PhysDrv [$phy] -a$adp
    sleep 2
    $_CMD_RAID -PDPrpRmv -PhysDrv [$phy] -a$adp

    echo
    echo
    echo "Replace the physical disk (Adapter:$adp,  Enclosure:${raid[1]}, Slot:${raid[2]})"
    echo  "and anykey to continue"
    echo
    read x

    ar=( $($_CMD_RAID -PDGetMissing -a$adp | awk '{if ($1 == 0) printf "%s %s",$2,$3 }') )
    $_CMD_RAID -PdReplaceMissing -PhysDrv [$phy] -Array${ar[0]} -row${ar[1]} -a$adp
    $_CMD_RAID -PDRbld -Start -PhysDrv [$phy] -a$adp

    echo
    echo
    echo "Start rebuild the physical disk (Adapter:$adp,  Enclosure:${raid[1]}, Slot:${raid[2]})"
    echo
    echo
  done

}

_megaraid_progress() {
  local FAIL_DISKS _CMD_RAID
   _CMD_RAID=$MegaRaid_CMD
  FAIL_DISKS="$( echo $($_CMD_RAID -PDList -aALL | while read line; do  if echo $line | grep "^Adapter" >/dev/null; then a=$(echo $line | awk '{print $2}' | sed "s/\#//g"); fi; if echo $line |grep "^Enclosure Device ID:" >& /dev/null ; then  e=$(echo $line | awk -F: '{print $2}' | sed "s/ //g"); else if echo $line |grep "^Slot Number:" >& /dev/null ; then  s=$(echo $line | awk -F: '{print $2}' | sed "s/ //g"); fi; if echo $line | grep "^Firmware state:" >& /dev/null; then state=$(echo $line | awk -F: '{print $2}' | awk -F, '{print $1}' | sed "s/ //g");  if [ "$state" != "Online" ]; then echo "$a:$e:$s"; fi ; fi; fi; done) )"


  while [ 1 ]; do
    for pdoff in $FAIL_DISKS; do
       raid=( $(echo $pdoff | sed "s/:/ /g" ) )
       adp=${raid[0]}
       phy="${raid[1]}:${raid[2]}"

       $_CMD_RAID -PDRbld -ShowProg -PhysDrv [$phy] -a$adp | grep "Rebuild Progress"
    done
    sleep $sleep
  done
}


_md() {
   echo not ready
}

_areca() {
          disks=( $($_areca_CMD rsf info | while read line; do
               if echo $line | grep "^[0-9]" >& /dev/null; then
                   disk_info=($line)
                   disk_info_num=$((${#disk_info[*]}-1))
                   echo "${disk_info[0]}:${disk_info[$(($disk_info_num-4))]}:${disk_info[$(($disk_info_num-1))]}:${disk_info[$disk_info_num]}"
               fi
          done) )

          chk_num=1
          vol_num=1
          pri_vol=0
          vol=($(echo "${disks[*]}" | sed "s/:/ /g" | awk '{printf "%s %s\n",$1,$5}'))
          vol_dnum=($(echo "${disks[*]}" | sed "s/:/ /g" | awk '{printf "%s %s\n",$2,$6}'))
          fail_disks="$($_areca_CMD disk info | grep -v -e "N.A." -e "^==" -e "ModelName" -e "^GuiErr" | while read line ; do
             if (($chk_num>$((${vol_dnum[$(($vol_num-1))]}+$pri_vol)))); then
                  vol_num=$(($vol_num+1))
                  pri_vol=$chk_num
             fi

             echo "$line" | grep "Failed" | awk -v voln=${vol[$(($vol_num-1))]} '{printf "%s:E%s:S%s\n",voln,$2,$4}'
             chk_num=$(($chk_num+1))
          done)"

          _RAID_VD=""
	  for disk_ii in ${disks[*]}; do
		    disk_info=( $(echo $disk_ii | sed "s/:/ /g")  )
		    _RAID_PD=$(( $_RAID_PD + ${disk_info[1]} ))
		    _RAID_VD="$_RAID_VD ${disk_info[0]}"
                    _RAW_SIZE[${disk_info[0]}]=${disk_info[2]}
          done
          if [ "$mode" == "v" ]; then
              kprint "   Physical Drives" "$_RAID_PD"
              kprint "   Virtual Drive #" "$(echo $_RAID_VD | sed "s/^ //g")"
          fi

          for N in $_RAID_VD; do
            _RAID_INFO=( $($_areca_CMD vsf info vol=$N | while read line; do
									if echo $line | grep "^Volume Capacity" >& /dev/null ; then
									   echo -n $line | awk -F: '{printf "%s ",$2}'
                                    elif echo $line | grep "^Raid Level" >& /dev/null ; then
									   echo -n $line | awk -F: '{printf "%s ",$2}' | sed "s/Raid//g"
                                    elif echo $line | grep "^Member Disks" >& /dev/null ; then
									   echo -n $line | awk -F: '{printf "%s ",$2}'
                                    elif echo $line | grep "^Cache Mode" >& /dev/null ; then
									   echo -n $line | sed "s/ //g" | awk -F: '{printf "%s ",$2}'
                                    elif echo $line | grep "^Volume State" >& /dev/null ; then
									   echo -n $line | awk -F: '{printf "%s ",$2}'
									fi
									done
									) )
            _RAID_LD_STATE[$N]=${_RAID_INFO[4]}
            _FAIL_DISKS=$(echo "$fail_disks" | awk -F: -v vol=$N '{if($1==vol) printf "%s:%s",$2,$3}')
            if [ "$mode" == "d" ]; then
              if [ "$(echo ${_RAID_LD_STATE[$N]}|sed "s/ //g")" != "Normal" ]; then
                  logger "$(basename $0): c$(($N - 1)) State" "${_RAID_LD_STATE[$N]}"
                  echo "$(basename $0): c$(($N - 1)) State" "${_RAID_LD_STATE[$N]} $([ -n "$_FAIL_DISKS" ] && echo "=>$_FAIL_DISKS")" >> /tmp/raid.email
              fi
            else
              if [ "$mode" == "v" ]; then
                  _RAID_VD_CACHE[$N]=${_RAID_INFO[3]}
                  _RAID_VD_LEVEL[$N]=${_RAID_INFO[1]}
                  _RAID_VD_SIZE[$N]=${_RAID_INFO[0]}
                  _RAID_VD_ND[$N]=${_RAID_INFO[2]}
                  kprint "    - vol $N Raid Level" "${_RAID_VD_LEVEL[$N]}"
                  kprint "    - vol $N Volume Size" "${_RAID_VD_SIZE[$N]}"
                  kprint "    - vol $N # of Physical Disk" "${_RAID_VD_ND[$N]}"
                  kprint "    - vol $N Physical Disk Size" "${_RAW_SIZE[$N]}"
                  kprint "    - vol $N Cache" "${_RAID_VD_CACHE[$N]}"
              fi
              kprint "    - vol $N State" "${_RAID_LD_STATE[$N]} $([ -n "$_FAIL_DISKS" ] && echo "=>$_FAIL_DISKS")"
            fi
          done

          if [ "$mode" == "d" ]; then
             if [ -f /tmp/raid.email ]; then
               echo  >> /tmp/raid.email
               echo "Checking time : $(date)" >> /tmp/raid.email
               echo "monitoring path : $0" >> /tmp/raid.email
               echo "help  : $(basename $0) -h" >> /tmp/raid.email
               for mail in $email ; do
                 mail -s $(hostname)_disk_information $mail < /tmp/raid.email
               done
               rm -f /tmp/raid.email
             fi
          fi
}

_3ware() {
          disks=( $($_3Ware_CMD info | grep "^c[0-9]" | awk '{printf "%s:%s ",$1,$4}') )

          if [ "$mode" != "d" ]; then
            for i in ${disks[*]}; do
              _RAID_PD=$(( $_RAID_PD + $(echo $i | awk -F: '{print $2}') ))
            done
          fi

          _RAID_VD=${#disks[*]}
          if [ "$mode" == "v" ]; then
              kprint "   Physical Drives" "$_RAID_PD"
              kprint "   Virtual Drives" "$_RAID_VD"
          fi

          for N in $(seq 1 $_RAID_VD); do
            _RAID_INFO=( $( $_3Ware_CMD /c$(($N - 1)) show all | grep RAID ) )
            _RAID_LD_STATE[$N]=${_RAID_INFO[2]}
            _FAIL_DISKS="$_FAIL_DISKS $($_3Ware_CMD /c$(($N - 1)) show all | grep "^p[0-9]" | awk -v nn=$(($N - 1)) '{if($2 != "OK" && $2 != "NOT-PRESENT") printf "c%s:%s ",nn,$1 }')"
            if [ "$mode" == "d" ]; then
              if [ "${_RAID_LD_STATE[$N]}" != "OK" ]; then
                  logger "$(basename $0): c$(($N - 1)) State" "${_RAID_LD_STATE[$N]}"
                  echo "$(basename $0): c$(($N - 1)) State" "${_RAID_LD_STATE[$N]}" >> /tmp/raid.email
              fi
            else
              if [ "$mode" == "v" ]; then
                  _RAID_VD_CACHE[$N]=${_RAID_INFO[7]}
                  _RAID_VD_LEVEL[$N]=$(echo ${_RAID_INFO[1]} | sed "s/RAID-//g")
                  _RAID_VD_SIZE[$N]=${_RAID_INFO[6]}
                  _RAID_VD_ND[$N]=$(echo ${disks[$(($N - 1))]} | awk -F: '{print $2}')
                  _RAW_SIZE[$N]=$( $_3Ware_CMD /c$(($N - 1)) show all | awk '{if ($2=="OK") printf "%s %s\n",$4,$5}' | head -n 1 )
                  kprint "    - c$(($N - 1)) Raid Level" "${_RAID_VD_LEVEL[$N]}"
                  kprint "    - c$(($N - 1)) Volume Size" "${_RAID_VD_SIZE[$N]}"
                  kprint "    - c$(($N - 1)) # of Physical Disk" "${_RAID_VD_ND[$N]}"
                  kprint "    - c$(($N - 1)) Physical Disk Size" "${_RAW_SIZE[$N]}"
                  kprint "    - c$(($N - 1)) Cache" "${_RAID_VD_CACHE[$N]}"
              fi
              kprint "    - c$(($N - 1)) State" "${_RAID_LD_STATE[$N]}"
            fi
          done

          if [ "$mode" == "d" ]; then
             if [ -n "$(echo $_FAIL_DISKS| sed "s/ //g")" ];then
                  logger "$(basename $0): 3Ware: Issued Disk's numbers : >${_FAIL_DISKS}<"
                  echo "$(basename $0): 3Ware: Issued Disk's numbers : $_FAIL_DISKS" >> /tmp/raid.email
             fi
             if [ -f /tmp/raid.email ]; then
               echo  >> /tmp/raid.email
               echo "Checking time : $(date)" >> /tmp/raid.email
               echo "monitoring path : $0" >> /tmp/raid.email
               echo "help  : $(basename $0) -h" >> /tmp/raid.email
               for mail in $email ; do
                 mail -s $(hostname)_disk_information $mail < /tmp/raid.email
               done
               rm -f /tmp/raid.email
             fi
          elif [ "$mode" == "v" ]; then
              kprint "    - Issued Disks" "$_FAIL_DISKS"
          fi
}

_lsi() {
          local netapp_ip mode
          mode=$1
          netapp_ip=$2
          if [ -n "$netapp_ip" ]; then
              netapp_cmd="$netapp_ip"
          else
              #Name, controllerA IP, controllerB IP, status
              netapp_info=( $(SMcli -d -v | head -n1) )
              (( ${#netapp_info[*]} > 7 )) && error_exit "Please try again to $(basename $0) -v -ip <NetAPP outbound IP>"
              netapp_cmd="-n ${netapp_info[0]}"
          fi

          #Volume group, Controllers, Drives, hotspare
          disk_info=($(SMcli $netapp_cmd -c "show storageArray healthStatus summary;" | grep -e "Drives:" -e "Controllers:" -e "Volume groups" -e "Total hot spare drives:" | awk -F: '{print $2}') )

          if [ "$mode" == "v" ]; then
              kprint "   Controllers" "${disk_info[1]}"
              kprint "   Physical Drives" "${disk_info[2]}"
              kprint "    - Hot spare drives" "${disk_info[3]}"
              kprint "   Volume Groups" "${disk_info[0]}"
          fi

          vol_num=0
          tmp_file=$(mktemp -u /tmp/mon_disk.XXXXXXXXXX)
          SMcli $netapp_cmd -c "show allVolumes;"| while read line; do
                echo $line | grep "^Volume name:" >& /dev/null && vol_num=$(($vol_num+1))
                if (($vol_num>0)); then
                    echo $line | grep "^Volume name:" >& /dev/null && echo "vol_name[$vol_num]=\"$(echo $line | awk -F: '{print $2}')\"" >> $tmp_file
                    echo $line | grep "^Volume status:" >& /dev/null && echo "vol_state[$vol_num]=\"$(echo $line | awk -F: '{print $2}')\"" >> $tmp_file
                    echo $line | grep "^Capacity:" >& /dev/null && echo "vol_size[$vol_num]=\"$(echo $line | awk -F: '{print $2}')\"" >> $tmp_file
                    echo $line | grep "^RAID level:" >& /dev/null && echo "vol_raid[$vol_num]=\"$(echo $line | awk -F: '{print $2}')\"" >> $tmp_file
                    echo $line | grep "^Read cache:" >& /dev/null && echo "vol_rcache[$vol_num]=\"$(echo $line | awk -F: '{print $2}')\"" >> $tmp_file
                    echo $line | grep "^Write cache:" >& /dev/null && echo "vol_wcache[$vol_num]=\"$(echo $line | awk -F: '{print $2}')\"" >> $tmp_file
                    echo $line | grep "^Flush write cache after (in seconds):" >& /dev/null && echo "vol_fwcache[$vol_num]=\"$(echo $line | awk -F: '{print $2}')\"" >> $tmp_file
                    echo $line | grep "^Write cache with mirroring:" >& /dev/null && echo "vol_mwcache[$vol_num]=\"$(echo $line | awk -F: '{print $2}')\"" >> $tmp_file
                    echo $line | grep "^Write cache without batteries:" >& /dev/null && echo "vol_bwcache[$vol_num]=\"$(echo $line | awk -F: '{print $2}')\"" >> $tmp_file
                    echo $line | grep "^Dynamic cache read prefetch:" >& /dev/null && echo "vol_dcache[$vol_num]=\"$(echo $line | awk -F: '{print $2}')\"" >> $tmp_file
                fi
          done
          if [ -f $tmp_file ]; then
            source $tmp_file
            for ((ii=1; ii<=${#vol_name[*]}; ii++)); do
              if [ "$mode" == "d" ]; then
                echo "Not yet"
              else
                if [ "$mode" == "v" ]; then
                  kprint "    - Vol name" "${vol_name[$ii]}"
                  kprint "    - Raid Level" "${vol_raid[$ii]}"
                  kprint "    - Volume Size" "${vol_size[$ii]}"
                  kprint "    - # of Physical Disk" "$(SMcli $netapp_cmd -c "show allDrives;" | grep "Associated volume group" | grep -w ${vol_name[$ii]} | wc -l)"
                  kprint "    - Read cache" "${vol_rcache[$ii]}"
                  kprint "    - Write cache" "${vol_wcache[$ii]}"
                  kprint "    - Write cache without batteries" "${vol_bwcache[$ii]}"
                  kprint "    - Write cache with mirroring" "${vol_mwcache[$ii]}"
                  kprint "    - Flush cache" "${vol_fwcache[$ii]} sec"
                  kprint "    - Dynamic cache read prefetch" "${vol_dcache[$ii]}"
                fi
                kprint "    - State" "${vol_state[$ii]}"
              fi
            done
            rm -f $tmp_file
          fi

          if [ "$mode" == "d" ]; then
              echo "Not yet"
          elif [ "$mode" == "v" ]; then
              kprint "    - Issued Disks" "SMcli $netapp_cmd -c \"show allDrives;\" CLI cmd will be helpful"
          fi
}

echo
kprint "<< Check Disk/Raid >>"
[ "$mode" == "d" ] && logger "$(basename $0) start"

lloop=1
while [ 1 ] ; do
   df -h 2>/dev/null | grep "^/dev/" | while read line ; do
        disk=( $line )
        if [ "$mode" == "d" ]; then
           [ -f /tmp/raid.email ] && rm -f /tmp/raid.email
           if (( $(echo ${disk[4]} | sed "s/%//g") >= $threshold )); then
              logger "$(basename $0): ${disk[5]} used over ${disk[4]}"
              echo "$(basename $0): ${disk[5]} used over ${disk[4]}" > /tmp/raid.email
           fi
        else
           if [ "$mode" == "v" ]; then
               kprint "${disk[5]}"  "${disk[4]}"
           fi
        fi
   done

   _RAID_CARD=$(lspci | grep -i raid | grep -w Areca > /dev/null && echo Areca)
   [ -n "$_RAID_CARD" ] || _RAID_CARD=$(lspci | grep -i raid | grep -w 3ware > /dev/null && echo 3ware)
   [ -n "$_RAID_CARD" ] || _RAID_CARD=$(lspci | grep -i raid | grep -w MegaRAID > /dev/null && echo MegaRaid)
   [ -n "$_RAID_CARD" ] || _RAID_CARD=$(lspci | grep -i raid | grep -w Areca > /dev/null && echo Areca)
   [ -n "$_RAID_CARD" ] || _RAID_CARD=$(ls /dev/md* 2> /dev/null | grep "/dev/md" > /dev/null && echo MD)
   [ -n "$_RAID_CARD" ] || _RAID_CARD=$(lspci -vv |grep LSI | grep Fusion-MPT >/dev/null && echo NetAPP)

   if [ "$mode" == "v" ]; then
       [ "$mode" == "d" ]   || kprint "Raid Info"  "$_RAID_CARD"
   fi
   if [ "$_RAID_CARD" == "MegaRaid" ]; then
       _megaraid $mode
   elif [ "$_RAID_CARD" == "3ware" ]; then
       _3ware $mode
   elif [ "$_RAID_CARD" == "Areca" ]; then
       _areca $mode
   elif [ "$_RAID_CARD" == "MD" ]; then
       _md $mode
   elif [ "$_RAID_CARD" == "NetAPP" ]; then
       _lsi "$mode" "$netapp_ip"
   fi
   #[ "$mode" == "d" ] && sleep $sleep || break
   if [ "$mode" != "d" ]; then
      if (( $lloop  >= $loop )) ; then
         break
      fi
      lloop=$(($lloop+1))
   fi
   sleep $sleep
done

[ "$replace" == "r" ] && _megaraid_replace
[ "$progress" == "p" ] && _megaraid_progress
