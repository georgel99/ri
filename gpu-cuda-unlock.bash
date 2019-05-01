#!/bin/bash

# Based on the epilog script at:
# https://github.com/kyamagu/sge-gpuprolog/blob/master/epilog.sh
#
# Remove lock-dirs that were used to assign specific GPUs to jobs,
#
# NB: An exit code of 100 puts the job in to error, not the queue.
#     But if there's a problem we might want to prevent any further
#     jobs landing on a node but putting the queue in to error.
#
# george.leaver@manchester.ac.uk, Research Infrastructure, August 2018

PATH=/bin:/usr/bin

### We'll get SGE_GPU_IDS in the job's env
ENV_FILE=$SGE_JOB_SPOOL_DIR/environment
if [ ! -f $ENV_FILE ] || [ ! -r $ENV_FILE ]; then
    echo "ERROR: Cannot read from job environment ($ENV_FILE)"

    # Let's put the queue in to error - we don't want further jobs landing here
    exit 1
fi

### Remove lock-dirs
device_ids=$(grep SGE_GPU_IDS $ENV_FILE | \
    sed -e "s/,/ /g" | \
    sed -n "s/SGE_GPU_IDS=\(.*\)/\1/p")

# No need to use $SGE_JOBEXIT_STAT. See 'man sge_conf' for description of this var in an epilog script.
# If a job exits with non-zero (e.g., 99 to requeue) then it all still behaves as expected.
# The epilog retval doesn't break that.
retval=0

for device_id in $device_ids; do
    lockdir=/tmp/lock-gpu$device_id
    if [ -d $lockdir ]; then
	rm -rf $lockdir 2>/dev/null
	if [ $? != 0 ]; then
	    echo "ERROR: failed to remove lock directory $lockdir for GPU $device_id on `hostname -s`"

	    # Let's put the queue in to error - we don't want further jobs landing here
	    retval=1
	fi
    fi
done
exit $retval
