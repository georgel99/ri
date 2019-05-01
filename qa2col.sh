#!/bin/bash

# Convert qacct multi-row records to multi-column records.
# Only print certain fields.
#
# Use this to inspect qacct info for job arrays where you'll
# have a lot of records for a single job. Each job array task
# is given a distinct qacct record.
#
# Usage qa2col.sh qacct-file.txt
#
# where the qacct-file.txt is generate by doing something like:
#
# qacct -j jobid > qacct-file.txt
#
# -gwl Jan 14
#
# -------------- Configuation (edit me) ---------------
# Edit this list of default field names (see below for qacct list)
FIELDS=( jobnumber taskid hostname exit_status qsub_time start_time end_time ru_wallclock slots ru_maxrss maxvmem io jobname )

# Sort on taskid (1st field-name in list above) by default
SORT_ON=1
# -------------- Configuation (edit me) ---------------

#### We'll grep for #f to print this table when displaying help ####
#f qacct fields
#f ------------
#f qname         granted_pe        ru_nswap
#f hostname      slots             ru_inblock
#f group         failed            ru_oublock
#f owner         exit_status       ru_msgsnd
#f project       ru_wallclock      ru_msgrcv
#f department    ru_utime          ru_nsignals
#f jobname       ru_stime          ru_nvcsw
#f jobnumber     ru_maxrss         ru_nivcsw
#f taskid        ru_ixrss          cpu
#f account       ru_ismrss         mem
#f priority      ru_idrss          io
#f qsub_time     ru_isrss          iow
#f start_time    ru_minflt         maxvmem
#f end_time      ru_majflt         arid
#f
#f Run 'man accounting' for more info on fields.
#f

progname=`echo $0 | sed "s/.*\/\(.*\)/\1/g"`

[ $# -eq 0 ] && echo "Usage: $progname qacct-output-file [sort-field-num] [-f field1,field2,...]" && \
                echo "Default fields: `echo ${FIELDS[@]} | tr " " ","`" && \
		echo "To see a list of all fields run '$progname -h'" && exit 1
[ "$1" == "-h" ] && grep '^#f' $0 | sed -e 's/#f[ ]*//g' && exit 1
[ ! -f "$1" ] &&  echo "$progname Cannot open qacct output file $1" && exit 1

INFILE=$1

if ( [ "$2" -eq "$2" 2>/dev/null ] && [ -n "$2" ] && [ "$2" -gt 0 ] && [ "$2" -le ${#FIELDS[@]} ] ); then
  SORT_ON=$2
  shift
fi
COMMA_FIELDS=""
if ( [ -n "$2" ] && [ "$2" == "-f" ] && [ -n "$3" ] ); then
  COMMA_FIELDS=$3
#elif ( [ -n "$3" ] && [ "$3" == "-f" ] && [ -n "$4" ] ); then
#  COMMA_FIELDS=$4
fi
if [ -n "$COMMA_FIELDS" ]; then
  FIELDS=( `echo "$3" | sed 's/,/ /g'` )
fi

cat $INFILE | sed -e 's/.prv.*estate//g' | \
  awk -v fields="${FIELDS[*]}" \
'BEGIN {
  # Each FIELD is separated by a newline - see qacct output
  FS="\n"
  # Each RECORD is separated by this thing - see qacct output
  RS="==============================================================\n"
  # Create an array containing the field names we passed in on command-line
  numf=split(fields,outfields," ")
}

# Output from qacct has a blank first record (a RS is at top)
NR == 1 {next}

# Use first record to print header and calc col widths
NR==2 {
  for (i=1; i<=NF; i++) {
    split($i,tmp," ")
    tmp_val=$i
    sub( /^[^ ]+[ ]+/, "", tmp_val); 
    sub( /[ ]+$/, "", tmp_val)    
    widths[tmp[1]] = max(length(tmp[1]), length(tmp_val))
  }
  for ( i=1; i<=numf; i++ ) {
    printf( "%*-s  ", widths[outfields[i]], outfields[i] )
  }
  printf( "\n" )
}

# All records (including the first) - split field in to key/value pair and print the value
NR>1{ for (i=1; i<=NF; i++) {
    # EG: $i is start_time   Wed Jan  8 08:39:44 2014

    # Only want first word from $i i.e start_time
    split($i,tmp," ")
    # Want all but the first element (with w/s after 1st elem removed) i.e. Wed Jan  8 08:39:44 2014
    sub( /^[^ ]+[ ]+/, "", $i); 
    sub( /[ ]+$/, "", $i)

    # Make associative array: fieldvals[start_time] = Wed Jan  8 08:39:44 2014
    fieldvals[tmp[1]]=$i
  }
  # Remove spaces from time/data entries
  gsub(/ /, "-", fieldvals["qsub_time"])
  gsub(/ /, "-", fieldvals["start_time"])
  gsub(/ /, "-", fieldvals["end_time"])

  # Now print only those field we have been asked to
  for (i=1; i<=numf; i++) {
    printf( "%*s  ", widths[outfields[i]], fieldvals[outfields[i]] )
  }
  printf( "\n" );
}

function max(a,b)   {return(( a > b ) ? a : b)}
' | \
  (read -r; printf "%s\n" "$REPLY"; sort -g -k $SORT_ON)
# Last line is to keep the header at the top then sort


