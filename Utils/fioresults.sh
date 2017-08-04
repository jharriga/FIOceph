#!/bin/bash
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# BASH script to echo FIO results from run directories 
# expects one argument, pathname to results directory
#

path=${1%/}
blksz_list="4k 64k 1024k"

##############################################
# SCRIPT
#----------------------------------------------

if [ ! -d "$path" ]; then
  echo "directory does not exist - exiting"
  exit
fi

for bs in $blksz_list; do
  # start with null output strings
  bw1=""
  bw2=""
  lat=""

  this_glob="${path}/*_BS${bs}.log"
  filecnt="$( ls $this_glob | wc -l )"

  declare -i loopcnt=0
  for fname in $this_glob; do
    
    if [ $loopcnt -eq 0 ]; then
      iod="$( awk 'BEGIN { FS="=" } /^iodepth=/ {print $2;exit;}' ${fname} )"
      ioeng="$( awk 'BEGIN { FS="=" } /^ioengine=/ {print $2;exit;}' ${fname} )"
      oper="$( awk 'BEGIN { FS="=" } /^rw=/ {print $2;exit;}' ${fname} )"
      echo "--------------------------------------------------------"
      echo "FIO settings: bs=$bs rw=$oper iodepth=$iod ioengine=$ioeng"
      echo "  BS${bs} -> Found ${filecnt} results files"
      echo "-------------"
    fi
    loopcnt=$((loopcnt+1))
    
    grepstr1=""
    grepstr2=""
    case $oper in 
      read|randread)
        grepstr1="READ:"
        ;;
      write|randwrite)
        grepstr1="WRITE:"
        ;;
      randrw)
        grepstr1="READ:"
        grepstr2="WRITE:"
        ;;
    esac;

#    tmpbw1="$( grep ${grepstr1} ${fname} )"
# Get and print the bandwidth stats
    readBW="$( awk 'BEGIN { FS="," } \
      /READ: bw=/ {print $1$2}' ${fname} )"
    writeBW="$( awk 'BEGIN { FS="," } \
      /WRITE: bw=/ {print $1$2}' ${fname} )"
#    echo "$oper  $grepstr1   $readBW"
#    if [ "$grepstr2" != "" ]; then
#      tmpbw2="$( grep ${grepstr2} ${fname} )"
#      bw2="$( awk 'BEGIN { FS="," } /${grepstr2} bw=/ {print $2}' ${fname} )"
#    fi
# Get and print the latency stats
    tmplat="$( grep -h "[^a-z]lat ([m-u]sec):" ${fname} )"
    unit="$( echo ${tmplat} | awk 'BEGIN { FS=":" } /lat/ {print $1}' )"
    lat="$( echo ${tmplat} | awk 'BEGIN { FS="," } /avg=/ {print $3}' )"
    stdev="$( echo ${tmplat} | awk 'BEGIN { FS="," } /stdev=/ {print $4}' )"

    # echo the results line(s)
    echo "${fname##*/}:"
    if [ "$readBW" != "" ]; then
        echo -e "${readBW}\n   ${unit}${lat} ${stdev}\n" 
    fi
    if [ "$writeBW" != "" ]; then
        echo -e "${writeBW}\n   ${unit}${lat} ${stdev}\n" 
    fi
  done

done
echo "----------------------------"

# END

