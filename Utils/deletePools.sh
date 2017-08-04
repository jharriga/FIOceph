#!/bin/bash
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# BASH script to automate teardown of RBD and ISCSI 
# comparision testing
#
# USAGE: $ cat remove.sh | ssh gprfc093

#poolname_list="rbdTest krbdTest librbdTest iscsiTest"
poolname_list="krbdTest librbdTest iscsiTest"

#--------------------------------------------------
# Create pool 
# Requires one passed arg - poolname
# - first ensure it does not already exist (unlikely)
# - allow user to remove if it exists 
function deletePool {
    local name=$1

    ceph osd pool delete ${name} ${name} --yes-i-really-really-mean-it
    if [ $? -ne 0 ]; then
        echo "pool $name cannot be deleted - exit"
        exit 1
    fi

}   # END deletePool

#--------------------------------
# Remove RBD devices. 
# Requires two passed arg: 
#   $1 = number of devices to delete
#   $2 = poolname
function removeRBD {
    local cnt=$1
    local pname=$2
    for (( i=1; i<=${cnt}; i++ )); do
      img_name="${pname}-${i}"
      rbd rm ${img_name}
    done
}    # END createRBD

#----------------------------------------------
# END FUNCTIONS
##############################################

##############################################
# SCRIPT
#----------------------------------------------
echo "Start: " `date`

# Delete the pools and images 
for poolname in ${poolname_list}; do
    # Remove the RBD images
    if [ $poolname != "iscsiTest" ]; then
        removeRBD ${devcnt} ${poolname}
        echo "Removed RBD images in pool: ${poolname}" 
    fi

    deletePool ${poolname}
    echo "Deleted pool: ${poolname}" 
done

echo "----------------------------"
echo "Completed: " `date`

