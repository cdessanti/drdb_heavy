#!/bin/bash
HEAVYAI_USER=${HEAVYAI_USER:-"admin"}
HEAVYAY_PASSWORD=${HEAVYAY_PASSWORD:-"HyperInteractive"}
HEAVYAI_DATABASE=${HEAVYAI_DATABASE:-"heavyai"}

if [ $# -eq 0 ]; then
  echo "warning: no threshold supllied using the default of 80%"
  exit 1
fi
IFS="
"
for i in $(nvidia-smi --query-gpu memory.total,memory.used --format=csv,nounits,noheader)
do
  IFS=, read total used <<< $i
  let percentage_used=${used}*100/${total}
  echo $total $used $percentage_used
  if [ $percentage_used -gt $1 ]; then
    echo "/opt/heavyai/bin/heavysql -q -u $HEAVYAI_USER -p $HEAVYAY_PASSWORD $HEAVYAI_DATABASE"
    echo "alter system clear gpu memory;" | /opt/heavyai/bin/heavysql -q -u $HEAVYAI_USER -p $HEAVYAY_PASSWORD $HEAVYAI_DATABASE
    echo "info: The threshold of $1 has been exceeded ($percentage_used). GPU caches cleared."
    break;
  fi
done
exit

