# FIOceph

Automates execution and monitoring of FIO jobfiles across multiple Ceph pools.
Supports these ceph pool types:
  * iSCSI
  * krbd
  * librbd
  
Run script is 'runPools.sh'
Pool and image details are defined in 'vars.shinc'

NOTE: librbd ioengine requires fio version 2.28 or later
