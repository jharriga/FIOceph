#!/bin/bash
#
#DEBUG   !/bin/bash -xv
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# runPools.sh
# ===========
#
# BASH script to automate Ceph device perf comparision testing
# Uses fio to execute tests
# Assumes the Ceph pools and devices already exist
#
# Pools: iscsiTest, krbdTest, librbdTest
# Devices: sixty 100GB LUNs in each pool
#   Device Naming scheme based on "$type": 
#        type=iscsi:        /dev/mapper/$client-isciTest-N (1-20)
#        type=krbd:         /dev/rbdN (1-60)
#        type=librbd:       $pool-N (1-60)
#        type=block:        /dev/sdN (aa-xx)
#        type=filesystem:   <mnt-path>
#
# Device STAGING pre-requisites: 
#   LIBRBD devices must have previously been created
#    > rbd list --pool <pname>
#       librbdTest-1
#       <... SNIP ...>
#       librbdTest-60
#   KRBD devices must be pre-mapped on all clients
#     > rbd showmapped
#         0  krbdTest krbdTest-1 -    /dev/rbd0
#         <... SNIP ...>
#         59 krbdTest krbdTest-60 -   /dev/rbd59 
#   iSCSI LUNs should be logged into by their clients
#     > iscsiadm -m session -P 3
#
# Test Writes results files in this dir structure:
#    /var/lib/pbench-agent/
#      /<timestamp>_$testType/$operation_$iodepth/
#         $pool_$client_$blocksize
#
# Be sure that pbench-agent-internal is installed on all clients
# and that 'pbench-register-tool-set' has been run on all clients
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

##############################################
# GLOBAL VARS
#----------------------------------------------
#
# Bring in user configured global vars
source ./vars.shinc

# Paths & filenames
# =================
fio_basename="/tmp/fiojob."       # Unique jobfile per client
fio_tmp="/tmp/jobfile.fio"        # remote fio jobfile name
pbdir="/var/lib/pbench-agent"
#
#----------------------------------------------
# END GLOBAL VARS
##############################################


##############################################
# FUNCTIONS
#----------------------------------------------
#
####
# device_chk - verifies that a device is available
# USES Global vars: pool
#
function device_chk {
  local host=$1           # client hostname
  local dtype=$2          # rbd, block, librbd, filesystem
  local devid=$3          # /dev/mapper/mpathe
  local pooldev           # appended pool and devid
  local client

  case $dtype in
    block|krbd|iscsi)
      echo "lsblk $devid >/dev/null 2>&1" | ssh $host
      if [ $? -ne 0 ]; then
          echo "DEVICE_CHK: $host reports $devid is not available"
          exit 1
      fi
      ;;
    librbd)
      pooldev="${pool}/${devid}"
      echo "rbd info $pooldev >/dev/null 2>&1" | ssh $host
      if [ $? -ne 0 ]; then
          echo "DEVICE_CHK: $host reports $pooldev is not available"
          exit 1
      fi
      ;;
    filesystem)
      echo "df $devid >/dev/null 2>&1" | ssh $host
      if [ $? -ne 0 ]; then
          echo "DEVICE_CHK: $host reports $devid is not available"
          exit 1
      fi
      ;;
    *) 
      echo "DEVICE_CHK: device type $dtype is not supported"
      exit 1
      ;;
  esac;
} # END device_chk

####
# writeFIOglobal - creates FIO jobfile global section
# Called by: gen_fiofile
#
function writeFIOglobal {
# Create FIO jobfile - GLOBAL section
  local fname=$1              # /tmp/jobfile.gprfc094

  source ./fioglobal.shinc

}   # END writeFIOglobal

####
# gen_jobfile - generates the FIO jobfile
# USES Global vars: pool and devcnt
# Calls writeFIOglobal function
#
function gen_jobfile {
  local jobfile=$1               # fio jobfile name
  local ptype=$2                 # pool type
  local lindex=$3                # start index for dev_array
  local lstride=$4               # stride for dev_array
  local jobstr                   # fio job string
  local strtmp                   # temp string var
  local string                   # string appended to fio section

  # Write the GLOBAL section
  writeFIOglobal ${jobfile}

  # Append to FIO jobfile - JOBS section
  declare -i cnt=0
  while [ $cnt -lt $devcnt ]; do
      cnt=$(( $cnt+1 ))
      devstr=${devarray[lindex]}
      jobstr="${cl}-${pool}-${ioengine}-${cnt}"
      # Append this job section to the jobfile
      if [ $ptype == "librbd" ]; then
          strtmp=$(printf "clientname=admin\npool=${pool}\n")
          string=${strtmp}$(printf "\nrbdname=${devstr}\n")
      else
          string="filename=${devstr}"
      fi

      source ./fiojobsection.shinc
      lindex=$(( $lindex+$lstride ))
  done

} # END gen_jobfile

####
# pop_devarray - populates the device array
#
function pop_devarray {
  local thistype=$1

  # Populate the entire device list for this Pool
  #  - device naming scheme depends on pool-type
  # Based on TYPE, set the device related variables
  declare -i start
  declare -i end

  case "$thistype" in
  librbd)
      start=$librbd_startindex
      end=$librbd_endindex
      for ((i=$start; i<=$end; i++)); do
          # append to the array of device names
          devarray=("${devarray[@]}" "${basename_librbd}${i}")
      done
      ;;
  krbd)
      start=$krbd_startindex
      end=$krbd_endindex
      for ((i=$start; i<=$end; i++)); do
          # append to the array of device names
          devarray=("${devarray[@]}" "${basename_krbd}${i}")
      done
      ;;
  iscsi)
      for iscsidev in $iscsidev_list; do
          devarray=("${devarray[@]}" "${iscsidev}")
      done
      ;;
  block)
      for blockdev in $blockdev_list; do
          devarray=("${devarray[@]}" "${blockdev}")
      done
      ;;
  filesystem)
      for fsdev in $fsdev_list; do
          devarray=("${devarray[@]}" "${fsdev}")
      done
      ;;
  *)
      echo "POP_DEVARRAY: Pool $pool has unknown type of $thistype"
      exit 1
      ;;
  esac;
} # END pop_devarray

#----------------------------------------------
# END FUNCTIONS
##############################################

##############################################
# MAIN SCRIPT
#----------------------------------------------
echo "Start: " `date`

# Name and create empty results directory
rundate=`date +'%Y%m%d-%H%M'`
testname="${rundate}_DEVCNT${devcnt}"
rundir="${pbdir}/${testname}"
mkdir "${rundir}"

# Outer FOR Loop - $pool_arr
let poolcnt=0
for pool in "${pool_arr[@]}"; do
  type="${type_arr[poolcnt]}"
  ioengine="${ioeng_arr[poolcnt]}"
#DEBUG
  echo "Outer FOR - POOL: $pool  TYPE: $type  IOENG: $ioengine"
  echo "Number of pools = ${#pool_arr[*]}  poolcnt = ${poolcnt}"
  poolcnt=$(( $poolcnt+1 ))

  # Populate device array
  declare -a devarray=()          # reset array for each pool
  pop_devarray $type

  # Ensure devarray is not empty
  if [ ${#devarray[@]} -eq 0 ]; then
      echo "Device array (devarray) is empty!"
      exit 1
  fi

  # Verify devices in devarray are available on Clients
  # Loop over the clientlist
  declare -i numclients=0
  for cl2 in $client_list; do
      echo "Checking for $type devices on $cl2"
      for thisdev in $devarray; do
          device_chk $cl2 $type $thisdev
      done
      numclients=$(( numclients+1 ))
  done

  # DEBUG
  echo "Number of devices in ${pool}: ${#devarray[@]}"
# DEBUG  echo "${devarray[@]}"
  # Device array has been populated
  #----------

  # Nested FOR loops of FIO parameter settings
  for oper in $operation_list ; do
    for iod in $iodepth_list; do
      # Name and create the 'oper_iod' results directory
      dirname="${pool}_${oper}_IOD${iod}"
      resultsdir="${rundir}/${dirname}"
      if [ ! -d "$resultsdir" ]; then
          mkdir "${resultsdir}"
      fi
      for bs in $blocksize_list; do
        #-------------------------------
        # Loop over the clientlist
        # Generate FIO jobfile for each Client
        # Copy FIO jobfile to each Client
        declare -i index=0
        for cl in $client_list; do
          # Create FIO jobfile to be used for this run
          fiofile="${fio_basename}${cl}"

          # Set stride based on pool type
          declare -i stride=0
          if [[ $type == "krbd" || $type == "librbd" ]]; then
              stride=$numclients
          else     # pool is iscsiTest, block or filesystem
              stride=1
          fi
      
          # function to generate FIO jobfile
          gen_jobfile $fiofile $type $index $stride
          # DEBUG
          #echo "** ${fiofile} **"; cat ${fiofile}

          # copy FIO jobfile to the client
          scp -q ${fiofile} "${cl}:${fio_tmp}"
          index=$(( $index+1 ))
        done
        # FIO jobfiles written
        #----------------------------------


        #-----------------------------------
        # Prepare for pbench-fio run
        #
        # Drop caches on clients
        pdsh -S -w $pdsh_clients "sync ; \
          echo 3 > /proc/sys/vm/drop_caches" &> /dev/null
        sleep 5
        echo " ---> ${testname}" 

        # Start remote ceph watch
        ssh ${cephServer} "ceph -w > /tmp/ceph-watch &" &> /dev/null

        #####################################
        # Invoke FIO run on the clients
        pdsh -S -w $pdsh_clients "cat ${fio_tmp} > /tmp/fioHOLD.log"
        pdsh -S -w $pdsh_clients "fio ${fio_tmp} &>> /tmp/fioHOLD.log"

        # FIO done - stop cephwatch process
        ssh ${cephServer} "pkill -f \"ceph -w\" "

        # Copy back FIO results and store the results
        for cl3 in $client_list; do
            resfile="${pool}_${cl3}_BS${bs}"
            this_result="${resultsdir}/${resfile}.log"
            scp -q "${cl3}:/tmp/fioHOLD.log" ${this_result}
        done

        # Copy back cephwatch results
        cephwatch="${resultsdir}/ceph-watch.${pool}_BS${bs}"
        scp -q ${cephServer}:/tmp/ceph-watch ${cephwatch}

        #----------------------------------
        # pbench-fio done - Cleanup and collect results
        # Move pbench-agent results dir and logfile to resultsdir
#        pbenchdir=`ls -rtd /var/lib/pbench-agent/fio_*/ |tail -1`
#        mv ${pbenchdir} ${resultsdir}
#        mv ${testname}.log ${resultsdir}
#        echo "pbenchdir: ${pbenchdir}"    # DEBUG
        echo "resultsdir: ${resultsdir}" 
        echo "cephwatch: ${cephwatch}"  
        #----------------------------------

      done  # end FOR $bs
     done   # end FOR $iod
    done    # end FOR $oper

    # Completion timestamp
    echo -e "---------------\n"
    echo "Completed pool = ${pool}: " `date`
    echo "Results are at: ${rundir}"
    echo -e "+++++++++++++++++++++++++++++++++++++++++\n"

done    # end FOR $pool

# Completion timestamp
echo "Completed all tests: " `date`
echo " *** DONE ***"

#
#----------------------------------------------
# END SCRIPT
##############################################
