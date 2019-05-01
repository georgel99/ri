#!/bin/bash

# Work out how long a job waited based on the qsub_time and start_time fields in the qacct output.
#
# We assume the qacct output has been run through qa2col so that we have something like:
#
# jobnumber  taskid  exit_status  qsub_time                 start_time                end_time                  ru_wallclock  slots  
#    10043       1          127  Thu Oct 15 14:45:58 2015  Thu Oct 15 14:46:07 2015  Thu Oct 15 14:46:07 2015             0      1  
#    10043       2          127  Thu Oct 15 14:45:58 2015  Thu Oct 15 14:46:07 2015  Thu Oct 15 14:46:07 2015             0      1  
#    10044       1          127  Thu Oct 15 14:47:53 2015  Thu Oct 15 14:48:07 2015  Thu Oct 15 14:48:07 2015             0      1  
#    10044       2          127  Thu Oct 15 14:47:53 2015  Thu Oct 15 14:48:07 2015  Thu Oct 15 14:48:07 2015             0      1  
#    10045       1          127  Thu Oct 15 14:48:47 2015  Thu Oct 15 14:48:52 2015  Thu Oct 15 14:48:52 2015             0      1  
#
# The qsub_time and start_time fields can be anywhere in the list of columns.
#
# NOTE: later versions of qa2col replaces the spaces in the timestamps with a '-' to make field processing easier.
#       This script will support either version, detecting which format is used.
#
# The following will read lines from a file and do the date arithmetic (convert dates to seconds then subtract)
#
# Args: filename
#
#       filename is the qa2col output file. It must contain the qacct
#       fields qsub_time and start_time.
#

progname=$0

if [ $# -ne 1 ]; then
  echo "$progname qa2col-file"
  echo ""
  echo "   filename is the qa2col file to read containing qsub_time and start_time data"
  echo ""
  exit 1
fi

filename=$1

if ! [ -f $filename ]; then
  echo "$progname failed to open file $filename"
  exit 1
fi

# Find the qsub_time field
qsub_time_field=$(head -n 1 $filename | awk '{for (i=1;i<NF;i++) {if($i=="qsub_time") {print i; exit 0}} print 0;}')
if ( [ -z "$qsub_time_field" ] || [ "$qsub_time_field" == "0" ] ); then
  echo "$progname: Input file $filename does not contain the qsub_time field from qacct."
  exit 1
fi
# Field the start_time field
start_time_field=$(head -n 1 $filename | awk '{for (i=1;i<NF;i++) {if($i=="start_time") {print i; exit 0}} print 0;}')
if ( [ -z "$qsub_time_field" ] || [ "$qsub_time_field" == "0" ] ); then
  echo "$progname: Input file $filename does not contain the start_time field from qacct."
  exit 1
fi

# Increment the field number since 'cut' will see the leading space
# on each data line as an extra field.
((qsub_time_field++))
((start_time_field++))

# Determine if the timestamp is using spaces or '-' as the delim by
# looking for '-' in the first record's qsub_time field entry
# Note, tr -s ' ' removes repeated spaces to leave just one between the fields.
FIELDCHECK=$(tail -n +2 $filename | head -n 1 | tr -s ' ' | cut -f $qsub_time_field -d ' ')
NUMDASHES=$(echo "$FIELDCHECK" | grep -c -e '-')
if [ "$NUMDASHES" -gt 0 ]; then
    TIMESTAMP_SPACES=0
else
    TIMESTAMP_SPACES=1
fi    

if [ $TIMESTAMP_SPACES -eq 1 ]; then
    # Since a timestamp is actually 4 fields (the timestamps contain spaces)
    # we need to increment one of the field counts to allow for that.
    if [ $qsub_time_field -lt $start_time_field ]; then
        start_time_field=$((start_time_field+4))
    else
        qsub_time_field=$((qsub_time_field+4))
    fi  
    
    # Calculate the field range for 'cut'. The timestamps have spaces in them
    # so are actually several fields as far as 'cut' is concerned.
    # NOTE: The field range is a string: "N-M", not a single number.
    qsub_field_range="${qsub_time_field}-$((qsub_time_field+4))"
    start_field_range="${start_time_field}-$((start_time_field+4))"
else
    # If using '-' in the timestamps, the timestamps are just one field
    qsub_field_range=${qsub_time_field}
    start_field_range=${start_time_field}
fi

# Assume line one is a header line. 
# Keep spaces at start of lines (we allowed for that earlier)
IFS=''
read < $filename;
# Print the header line with an extra 'waited' column at the end
echo -e "$REPLY\tWaited"

# Process every data record in the file
tail -n +2 $filename | while read line; do
  fullline="$line"

  # If the timestamps have spaces in them they are actually several fields.
  # Note that the awk mktime() function wants a timestamp in a different
  # format so we can't convert the qacct timestamps to seconds. Hence we used 'date'.
  qsub_time=$(echo $line | tr -s ' ' | cut -f $qsub_field_range -d ' ' )
  start_time=$(echo $line | tr -s ' ' | cut -f $start_field_range -d ' ' )

  # If NOT using spaces in timestamps, replace the - with a space for use with 'date'
  if [ $TIMESTAMP_SPACES -eq 0 ]; then
      qsub_time=$(echo $qsub_time | sed 's/-/ /g')
      start_time=$(echo $start_time | sed 's/-/ /g')
  fi
  
  # Convert to seconds
  qsub_sec=$(date -d "$qsub_time" +%s)
  start_sec=$(date -d "$start_time" +%s)

  # Wait time in number of seconds
  numsecs=$(( start_sec-qsub_sec ))

  # Convert back to d:h:m:s
  waitdays=$(( numsecs/60/60/24 ))
  waithours=$(( numsecs/60/60%24 ))
  waitmins=$((numsecs/60%60))
  waitsecs=$(($numsecs%60))

 # Output the original record with the 'waited' field value appended
  echo -e "$line\t${waitdays}d:${waithours}h:${waitmins}m:${waitsecs}s";
done


