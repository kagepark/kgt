###################################
# Copyright (c) CEP Research Institude, All rights reserved. Since 2008
# Kage Park
# License : GPL
####################################
set_huge_page() {
   echo 1024 > /proc/sys/vm/nr_hugepages
   echo 3355443200 > /proc/sys/kernel/shmmax
   echo 3355443200 > /proc/sys/kernel/shmall
}
huge_pages() {
  RSH_STR="ssh -o ConnectTimeout=5 -o CheckHostIP=no -o StrictHostKeychecking=no "
  if [ "$KGT_MODE" == "xcat" ]; then
     RSH_HOST=$(echo $(nodels $(echo $* | sed "s/ /,/g") | grep -v "^n0"))
  else
     RSH_HOST=$(_k_make_hostname $*)
  fi

  for ii in $RSH_HOST; do
     printf "%17s\n" "$ii"
     trap 2
     aa=set_huge_page
     bb="$(declare -f $aa); $aa"
     $RSH_STR $ii "$bb" 2>/dev/null || \
     echo -n "Connection time out"
     echo
  done
}
