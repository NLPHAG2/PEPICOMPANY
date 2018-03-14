#!/bin/sh
#####################################################################################
###                                                                               ###
### SCRIPT TO ??                                                                  ###
###                                                                               ###
#####################################################################################
PATH="$PATH:/usr/local/bin"
export RUN_DIR="/home/??????" ### je eigen directory invullen
export SCRIPT_NAME=`basename $0`
export LOG_DIR="${RUN_DIR}"
export LOG_OUTPUT_FILE="${LOG_DIR}/"`basename $0 | cut -d"." -f1`".out"
export SPOOL_OUTPUT_FILE1="${LOG_DIR}/"`basename $0 | cut -d"." -f1`"1.lst"

function ZZ_abort {
  echo "Value returned for this part : ${ZZ_RETVALUE}" >> $LOG_OUTPUT_FILE 2>&1
  echo "ERROR: Errors found!"                          >> $LOG_OUTPUT_FILE 2>&1
  echo "ERROR: Aborting script!"                       >> $LOG_OUTPUT_FILE 2>&1
  echo "Script Finished : $(date)"                     >> $LOG_OUTPUT_FILE 2>&1
  exit 8
}

### oracle parameters setting
. /home/oracle/bin/client64.env 

echo "Script ${SCRIPT_NAME} Started : $(date)" > $LOG_OUTPUT_FILE 2>&1
echo " " >> $LOG_OUTPUT_FILE 2>&1
# ------------------------------------------------------------

sqlplus -s username/password@connectstring         >> $LOG_OUTPUT_FILE 2>&1         << EOF

WHENEVER  SQLERROR  EXIT 8
set serveroutput on size 99000
set pagesize 0
set lines 200
--set heading off
spool $SPOOL_OUTPUT_FILE1;
--
--Doe je sql of roep een script aan:

select to_char(sysdate, 'YYYY/MM/DD HH24:MI:SS') "Today" from dual;

--
spool off;
quit;
EOF

ZZ_RETVALUE=$?
echo "Value returned for ${SCRIPT_NAME} : ${ZZ_RETVALUE}" >> $LOG_OUTPUT_FILE 2>&1
if [ ${ZZ_RETVALUE} -ne 0 ]; then
  ZZ_abort
fi

echo "Script ${SCRIPT_NAME} Finished : $(date)" >> $LOG_OUTPUT_FILE 2>&1

#
exit 0

