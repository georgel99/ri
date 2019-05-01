#!/bin/bash

# Based on the prolog script at:
# https://github.com/kyamagu/sge-gpuprolog/blob/master/prolog.sh
#
# The JSV must add to the job env a variable SGE_NGPUS which
# gives the number of GPUS requested by the user. The Nvidia
# v100 exec hosts have a consumable complex so we know there
# will only ever be the correct number of GPUs requested.
#
# In here we decide which GPUs to use. We will create a lock-dir
# indicating which GPUs our job has grabbed. Other jobs will 
# fail to grab them and hence will land on other GPUs. The epilog
# script will clean away the lock-dirs.
#
# NB: exit 100 will put the job, not the queue in to error.
#     but it might be better to prevent any job landing on a node
#     that has a problem since this is likely to be lock-dirs that
#     were not removed by a previous job's epilog.
#
# george.leaver@manchester.ac.uk, Research Infrastructure, August 2018

PATH=/bin:/usr/bin

### FOR TESTING ON NON-GPU NODES ONLY
### function nvidia-smi { seq 0 3 | xargs -n1; }

### Function from Node-Health-Check - avoid nvidia-smi -L | ... |wc -l
function nhc_nv_gpu_count() {
     case $1 in
         (*[*]) echo 0;;         # glob failed
         (*) echo $#;;
     esac
}

### JSV should have set this in the job's environment
if [ -z "$SGE_NGPUS" ]; then
  echo "ERROR: JSV has not set SGE_NGPUS"
  exit 100
fi

### We'll set CUDA_VISIBLE_DEVICES in the job's env
ENV_FILE=$SGE_JOB_SPOOL_DIR/environment
if [ ! -f $ENV_FILE ] || [ ! -w $ENV_FILE ]; then
  echo "ERROR: Cannot write to job environment ($ENV_FILE)"
  exit 100
fi

GPUIDS=""
NUMASSIGNED=0

### Get a list of device IDs (0-3).
### Can get a randomized list. Better to grab devices in order?
# SHUFFLE="xargs shuf -e"
SHUFFLE=cat
# device_ids=$(nvidia-smi -L | cut -f1 -d":" | cut -f2 -d" " | $SHUFFLE)
n_devices=$(nhc_nv_gpu_count /proc/driver/nvidia/gpus/*)
device_ids=$(seq 0 $((n_devices-1)) | $SHUFFLE )
for device_id in $device_ids; do
    lockdir=/tmp/lock-gpu$device_id
    mkdir $lockdir 2>/dev/null
    if [ $? == 0 ]; then
	# record the job id inside the lock dir (might be useful for debugging)
        echo $JOB_ID > $lockdir/jobid

        # prolog needs to run as root to write to job environment file. Let the user own the lock-dir.
	chown ${SGE_O_LOGNAME}. $lockdir $lockdir/jobid
	GPUIDS="$GPUIDS $device_id"
	((NUMASSIGNED++))
	if [ $NUMASSIGNED -ge $SGE_NGPUS ]; then
	    break
	fi
    fi
done
if [ $NUMASSIGNED -lt $SGE_NGPUS ]; then
  echo "ERROR: Could only reserve $NUMASSIGNED of $SGE_NGPUS requested gpu devices on `hostname -s` for job $JOB_ID"

  # If there was a problem with lock-dirs then prevent any further jobs landing on this node
  # until the problem has been resolved.
  exit 1
fi

### Set the job's environment (SGE_NGPUS is already in the env - we add the following)
### Can also set directly CUDA_VISIBLE_DEVICES (and GPU_DEVICE_ORDINAL for AMD opencl)
ids=$(echo $GPUIDS | sed -e 's/^ //' -e 's/ /,/g')
echo NGPUS=$SGE_NGPUS >> $ENV_FILE
echo SGE_GPU_IDS="$ids" >> $ENV_FILE
echo CUDA_VISIBLE_DEVICES="$ids" >> $ENV_FILE
exit 0
