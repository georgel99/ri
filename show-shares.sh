#!/bin/bash

# Display items in share tree, shares and percentage of shares

TMPFILE=/tmp/sst-$$.tmp
qconf -sst | egrep 'prj|^   default' | sed 's/.prj//g' | sort > $TMPFILE

# Two pass awk (needs temp file twice)
awk -F= -vOFS='\t' \
'BEGIN {
   format="%-13s\t%d\t%.1f%%\n"
   headformat="%-13s\t%s\t%s\n"
   printf headformat, "Group","Shares","%age"
   printf headformat, "-----","------","----"
 } 
# First pass: Sum the 2nd column
NR==FNR {TOTALSHARES+=$2; next}

# Second pass: strip leading space from the group name and print every row
{sub(/[ ]*/,"",$1); printf format, $1, $2, ($2/TOTALSHARES*100)}

# Print totals 
END {
  printf headformat, "-----","------","----"
  printf format, sprintf("(%d groups)",FNR),TOTALSHARES, "100"
}
' $TMPFILE $TMPFILE 

rm -f $TMPFILE

