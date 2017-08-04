#!/bin/sh

TMPFILE="/tmp/tmp"
touch $TMPFILE

while [ true ]; do
#  hold1=$(ssh gprfc093 ceph -s)
#  hold2=$(echo $hold1 | grep 'recovery io' > $TMPFILE)
#  if [ $? -ne 0 ]; then
#    echo `date` `cat $TMPFILE`
  hold1=$(ssh gprfc093 ceph -s > "$TMPFILE" 2>&1)
  if [ $? -eq 0 ]; then
#    hold2=$(grep -iq 'recovery io' "$TMPFILE")
    hold2=$(grep -iq 'HEALTH_ERR' "$TMPFILE")
    if [ $? -eq 0 ]; then
      echo -n `date`; echo "recovery active: $hold2"
    else
      echo `date` " ...recovery completed"
      exit
    fi
  fi
  sleep 60
done
rm $TMPFILE

