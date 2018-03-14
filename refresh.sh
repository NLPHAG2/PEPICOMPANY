#!/bin/sh
#####################################################################################
###                                                                               ###
### SCRIPT TO REFRESH A SCHEMA FROM EDWP (all existing objects will be dropped)   ###
### usage: nohup refresh Schemaname &                                             ###
###                                                                               ###
#####################################################################################
PATH="$PATH:/usr/local/bin"
export RUN_DIR="/oracle/ssw01/admin/HY2D/local/refresh"
export SCRIPT_NAME=`basename $0`
export LOG_DIR="${RUN_DIR}"
export LOG_OUTPUT_FILE="${LOG_DIR}/"`basename $0 | cut -d"." -f1`".out"
export SPOOL_OUTPUT_FILE1="${LOG_DIR}/"`basename $0 | cut -d"." -f1`"1.lst"
export SPOOL_OUTPUT_FILE2="${LOG_DIR}/"`basename $0 | cut -d"." -f1`"2.lst"
export LSCHEMA=$1
export IMPLOG=ipdp$LSCHEMA.log
export ORACLE_SID=""
. /usr/local/bin/oraenv <<EOF
HY2D
EOF

echo "Script ${SCRIPT_NAME} Started : $(date)" > $LOG_OUTPUT_FILE 2>&1
echo " " >> $LOG_OUTPUT_FILE 2>&1
echo "Oracle SID : ${ORACLE_SID}" >> $LOG_OUTPUT_FILE 2>&1
echo " " >> $LOG_OUTPUT_FILE 2>&1

# Dropping objects for schema
# ------------------------------------------------------------
#
echo "Dropping Objects for Schema...."   >> $LOG_OUTPUT_FILE 2>&1
sqlplus -s '/ as sysdba'                 >> $LOG_OUTPUT_FILE 2>&1         << EOF
WHENEVER  SQLERROR  EXIT 8
set serveroutput on size 99000
set pagesize 0
set lines 200
--set heading off
spool $SPOOL_OUTPUT_FILE1;
--
@dropobjx.sql $LSCHEMA
--
purge dba_recyclebin;

create database link HY2P connect to SYSTEM identified by STM_HY2P using 'HY2PTCP';

SELECT * FROM USER_USERS@HY2P;

CREATE OR REPLACE DIRECTORY DATA_PUMP_DIR_PJJ AS '/oracle/ssw01/admin/HY2D/local/refresh';

GRANT READ, WRITE ON DIRECTORY SYS.DATA_PUMP_DIR_PJJ TO SYSTEM;
--
spool off;
quit;
EOF
SQL_RETVALUE=$?

echo "Value returned for Part 1 : ${SQL_RETVALUE}" >> $LOG_OUTPUT_FILE 2>&1

#
#
impdp userid="'/ as sysdba'" network_link=HY2P DIRECTORY=DATA_PUMP_DIR_PJJ LOGFILE=$IMPLOG SCHEMAS=$LSCHEMA EXCLUDE=USER REMAP_SCHEMA=$LSCHEMA:$LSCHEMA

cat $IMPLOG >> $LOG_OUTPUT_FILE 2>&1

# Cleaning Up
# ------------------------------------------------------------
#
echo " " >> $LOG_OUTPUT_FILE 2>&1
echo "Cleaning Up...."   >> $LOG_OUTPUT_FILE 2>&1
echo " " >> $LOG_OUTPUT_FILE 2>&1
sqlplus -s '/ as sysdba'                 >> $LOG_OUTPUT_FILE 2>&1         << EOF
WHENEVER  SQLERROR  EXIT 8
set serveroutput on size 99000
set pagesize 0
set lines 200
--set heading off
spool $SPOOL_OUTPUT_FILE2;

--

SELECT * FROM USER_USERS@HY2P;

REVOKE READ, WRITE ON DIRECTORY SYS.DATA_PUMP_DIR_PJJ FROM SYSTEM;

DROP DIRECTORY DATA_PUMP_DIR_PJJ;

DROP database link HY2P;
--
spool off;
quit;
EOF
SQL_RETVALUE=$?

echo "Value returned for Part 2 : ${SQL_RETVALUE}" >> $LOG_OUTPUT_FILE 2>&1


echo "Script Finished : $(date)" >> $LOG_OUTPUT_FILE 2>&1
mail -s "Script ${SCRIPT_NAME} Finished: " peter.hagman@atradius.com < $LOG_OUTPUT_FILE

#
exit 0

#!/bin/sh
#####################################################################################
###                                                                               ###
### SCRIPT TO EXPORT - IMPORT TBSL tables from dmp to HSLP                        ###
###  And create new CALCschema and synonyms in ECPP                               ###
###  parameters: schema name & old schema                                         ###
### PLEASE DO NOT REMOVE OR OVERWRITE ANY FILES IN /dbreorg/nlphag2 !             ###
###                                                                               ###
#####################################################################################
PATH="$PATH:/usr/local/bin"
export RUN_DIR="/oracle/ssw01/admin/HSLP/local/bin"
export SCRIPT_NAME=`basename $0`
export LOG_DIR="${RUN_DIR}"
export LOG_OUTPUT_FILE="${LOG_DIR}/"`basename $0 | cut -d"." -f1`".out"
export SPOOL_OUTPUT_FILE1="${LOG_DIR}/"`basename $0 | cut -d"." -f1`"1.lst"
export SPOOL_OUTPUT_FILE2="${LOG_DIR}/"`basename $0 | cut -d"." -f1`"2.lst"
export SPOOL_OUTPUT_FILE3="${LOG_DIR}/"`basename $0 | cut -d"." -f1`"3.lst"
export SPOOL_OUTPUT_FILE4="${LOG_DIR}/"`basename $0 | cut -d"." -f1`"4.lst"
export SPOOL_OUTPUT_FILE5="${LOG_DIR}/"`basename $0 | cut -d"." -f1`"5.lst"
export SPOOL_OUTPUT_FILE6="${LOG_DIR}/"`basename $0 | cut -d"." -f1`"6.lst"
export OLDSCHEMA=$1
export NEWSCHEMA=$2
export SCHEMAPART=`echo $NEWSCHEMA | cut -c 3-`
export CALCSCHEMA="CALC${SCHEMAPART}"
export NEWSCHEMATS="${NEWSCHEMA}DATA"
export OLDSCHEMATS="${OLDSCHEMA}DATA"
export NEWSCHEMATSlc=`echo $NEWSCHEMATS | tr "[A-Z]" "[a-z]" `
export EXPPAR=xpdp_sl.par
### export IMPPAR=ipdp_sl.par
export EXPDMP="${OLDSCHEMA}.dmp"
export IMPLOG="${NEWSCHEMA}i.log"
#####################################################################################
function ZZ_abort {
  echo "Value returned for this part : ${ZZ_RETVALUE}" >> $LOG_OUTPUT_FILE 2>&1
  echo "ERROR: Errors found!"                          >> $LOG_OUTPUT_FILE 2>&1
  echo "ERROR: Aborting script!"                       >> $LOG_OUTPUT_FILE 2>&1
  echo "Script Finished : $(date)"                     >> $LOG_OUTPUT_FILE 2>&1
  mail -s "Script ${SCRIPT_NAME} Finished: " peter.hagman@atradius.com < $LOG_OUTPUT_FILE
  exit 8
}

sudo /sysman/operators/mount_node_dbreorg

############################################ SID = EDWP #############################
export ORACLE_SID=""
. /usr/local/bin/oraenv <<EOF
EDWP
EOF

echo "Script ${SCRIPT_NAME} Started : $(date)" > $LOG_OUTPUT_FILE 2>&1
echo " " >> $LOG_OUTPUT_FILE 2>&1
echo "Oracle SID : ${ORACLE_SID}" >> $LOG_OUTPUT_FILE 2>&1
echo " " >> $LOG_OUTPUT_FILE 2>&1

#
# Check space on file systems
# ------------------------------------------------------------
export fschoice="NONE"
echo "Check space on file systems : $(fschoice)" >> $LOG_OUTPUT_FILE 2>&1

for fsnm in $(df -g | grep 'hslp/db' | awk '{print $7}')
do
   # Convert the file size to a numeric value
   freegb=$(df -g | grep $( echo $fsnm ) | awk '{print $3}')

   # If any filesystem has less than 40GB, issue an alert
   if [ $freegb  -lt 40 ]
   then
      echo  "Oracle filesystem $fsnm has less than 40gb free."  >> $LOG_OUTPUT_FILE 2>&1
      echo  "Free space is $freegb gb "                         >> $LOG_OUTPUT_FILE 2>&1
   else
      echo  "Oracle filesystem $fsnm can be used."              >> $LOG_OUTPUT_FILE 2>&1
      echo  "Free space is $freegb gb "                         >> $LOG_OUTPUT_FILE 2>&1
      if [ $fschoice = "NONE" ]
      then
        export fschoice="${fsnm}"                               >> $LOG_OUTPUT_FILE 2>&1
      fi
   fi
done

if [ $fschoice = "NONE" ]
then
  echo "No Space left on the filesystems for HSLP script will abort"  >> $LOG_OUTPUT_FILE 2>&1
  ZZ_RETVALUE=8
  echo "Value returned for Step 0 : ${ZZ_RETVALUE}" >> $LOG_OUTPUT_FILE 2>&1
  ZZ_abort
else
  echo "Filesystem $fschoice has been chosen"                  >> $LOG_OUTPUT_FILE 2>&1
  export FILESYSNO=$fschoice
fi

############################################ SID = HSLP #############################
export ORACLE_SID=""
. /usr/local/bin/oraenv <<EOF
HSLP
EOF
#
# Creating New Tablepace and Schema
# ------------------------------------------------------------
echo "############### SID = HSLP ############## " >> $LOG_OUTPUT_FILE 2>&1
echo "Creating New Tablepace and Schema...."   >> $LOG_OUTPUT_FILE 2>&1
echo " " >> $LOG_OUTPUT_FILE 2>&1
sqlplus -s '/ as sysdba'                 >> $LOG_OUTPUT_FILE 2>&1         << EOF
WHENEVER  SQLERROR  EXIT 8
set serveroutput on size 99000
set pagesize 0
set lines 200
--set heading off
spool $SPOOL_OUTPUT_FILE3;
--
CREATE OR REPLACE DIRECTORY DATA_PUMP_DIR_DBREORG AS '/dbreorg/nlphag2';
GRANT READ, WRITE ON DIRECTORY SYS.DATA_PUMP_DIR_DBREORG TO SYSTEM;

CREATE TABLESPACE $NEWSCHEMATS DATAFILE
  '${FILESYSNO}/${NEWSCHEMATSlc}01.dbf' SIZE 10240M AUTOEXTEND ON NEXT 10M MAXSIZE 20480M,
  '${FILESYSNO}/${NEWSCHEMATSlc}02.dbf' SIZE 10240M AUTOEXTEND ON NEXT 10M MAXSIZE 20480M
LOGGING
EXTENT MANAGEMENT LOCAL AUTOALLOCATE
BLOCKSIZE 8K
SEGMENT SPACE MANAGEMENT MANUAL
FLASHBACK ON;

CREATE USER $NEWSCHEMA
  IDENTIFIED BY NOONE_KN0WS
  DEFAULT TABLESPACE $NEWSCHEMATS
  TEMPORARY TABLESPACE TEMP
  PROFILE EXCEPT
  ACCOUNT UNLOCK;
  GRANT SELECT_CATALOG_ROLE TO $NEWSCHEMA;
  GRANT RESOURCE TO $NEWSCHEMA;
  GRANT CONNECT TO $NEWSCHEMA;
  ALTER USER $NEWSCHEMA DEFAULT ROLE ALL;
  GRANT CREATE SESSION TO $NEWSCHEMA;
  GRANT SELECT ANY TABLE TO $NEWSCHEMA;
  GRANT SELECT ANY DICTIONARY TO $NEWSCHEMA;
  REVOKE UNLIMITED TABLESPACE FROM $NEWSCHEMA;
  ALTER USER $NEWSCHEMA QUOTA UNLIMITED ON $NEWSCHEMATS;
--
spool off;
quit;
EOF
ZZ_RETVALUE=$?
echo "Value returned for Creating New Tablepace and Schema : ${ZZ_RETVALUE}" >> $LOG_OUTPUT_FILE 2>&1
if [ ${ZZ_RETVALUE} -ne 0 ]; then
  ZZ_abort
fi
#
# IMPORTING TABLES
# ------------------------------------------------------------
echo "IMPORTING TABLES........"          >> $LOG_OUTPUT_FILE 2>&1
#
impdp userid="'/ as sysdba'" DIRECTORY=DATA_PUMP_DIR_DBREORG DUMPFILE=$EXPDMP \
                             LOGFILE=$IMPLOG \
                                REMAP_SCHEMA=$OLDSCHEMA:$NEWSCHEMA \
                                EXCLUDE=GRANT \
                                REMAP_TABLESPACE=$OLDSCHEMATS:$NEWSCHEMATS \
                                REMAP_TABLESPACE=S2Q3INDL:$NEWSCHEMATS

ZZ_RETVALUE=$?
cat /dbreorg/nlphag2/$IMPLOG >> $LOG_OUTPUT_FILE 2>&1
echo "Value returned for IMPORT : ${ZZ_RETVALUE}" >> $LOG_OUTPUT_FILE 2>&1
if [ ${ZZ_RETVALUE} -eq 1 ]; then
  ZZ_abort
fi
#
# Cleaning Up
# ------------------------------------------------------------
echo " " >> $LOG_OUTPUT_FILE 2>&1
echo "Cleaning Up...."   >> $LOG_OUTPUT_FILE 2>&1
echo " " >> $LOG_OUTPUT_FILE 2>&1
sqlplus -s '/ as sysdba'                 >> $LOG_OUTPUT_FILE 2>&1         << EOF
WHENEVER  SQLERROR  EXIT 8
set serveroutput on size 99000
set pagesize 0
set lines 200
--set heading off
spool $SPOOL_OUTPUT_FILE4;
--
ALTER TABLESPACE $NEWSCHEMATS READ ONLY;
REVOKE READ, WRITE ON DIRECTORY SYS.DATA_PUMP_DIR_DBREORG FROM SYSTEM;
DROP DIRECTORY DATA_PUMP_DIR_DBREORG;
--
spool off;
quit;
EOF
ZZ_RETVALUE=$?
echo "Value returned for Cleaning Up : ${ZZ_RETVALUE}" >> $LOG_OUTPUT_FILE 2>&1
if [ ${ZZ_RETVALUE} -ne 0 ]; then
  ZZ_abort
fi

############################################ SID = ECPP #############################
export ORACLE_SID=""
. /usr/local/bin/oraenv <<EOF
ECPP
EOF
#
# Creating New Schema and Synonyms
# ------------------------------------------------------------
echo "############### SID = ECPP ################ " >> $LOG_OUTPUT_FILE 2>&1
echo "Creating New Schema and Synonyms...."   >> $LOG_OUTPUT_FILE 2>&1
echo " " >> $LOG_OUTPUT_FILE 2>&1
sqlplus -s '/ as sysdba'                 >> $LOG_OUTPUT_FILE 2>&1         << EOF
WHENEVER  SQLERROR  EXIT 8
set serveroutput on size 99000
set pagesize 0
set lines 200
--set heading off
spool $SPOOL_OUTPUT_FILE5;
--
CREATE USER $CALCSCHEMA
  IDENTIFIED BY NOONE_KN0WS
  DEFAULT TABLESPACE CALCUL
  TEMPORARY TABLESPACE TEMP
  PROFILE EXCEPT
  ACCOUNT UNLOCK;
  GRANT SELECT_CATALOG_ROLE TO $CALCSCHEMA;
  ALTER USER $CALCSCHEMA DEFAULT ROLE ALL;
  GRANT CREATE SESSION TO $CALCSCHEMA;
  GRANT CREATE SYNONYM TO $CALCSCHEMA;
ALTER USER $CALCSCHEMA
  GRANT CONNECT THROUGH CALCULQ4;
--
create synonym $CALCSCHEMA.PKG_SET_DATES_CONTEXT for EDWQ3.PKG_SET_DATES_CONTEXT@EDW_SEM_LAY;
--
Declare
--
stmt    Varchar2(200);
intgr   Integer;
schem   varchar2(30) := upper('$NEWSCHEMA');
synown  varchar2(30) := upper('$CALCSCHEMA');
db_link varchar2(30) := upper('HSL_SEM_LAY');
--
Tot  Integer         := 0;
Existingsyns Integer := 0;
Errs Integer         := 0;
--
Msg    Varchar2(400);
--
AlreadyExists  Exception;
Pragma Exception_init(AlreadyExists,-955);
--
Cursor C1 Is
    Select   Owner,Object_Name,Object_Type
    From     Dba_Objects@HSL_SEM_LAY
    Where    Owner = schem
    And      Object_Type In  ('PROCEDURE','TABLE','VIEW','FUNCTION','MATERIALIZED VIEW','SEQUENCE','PACKAGE')
    And      Object_Name Not Like 'BIN$%'
    And      Object_Name Not In  (Select Synonym_Name From Dba_Synonyms Where Owner = synown And Table_Owner = schem);
--
Begin
  Select count(Synonym_Name)  into Existingsyns From Dba_Synonyms Where Owner = synown And Table_Owner = schem;
  For Xx In C1 Loop
--
  Begin
--
     If synown = 'PUBLIC' then
       stmt  := 'Create PUBLIC synonym '||Xx.Object_Name||' for '||Schem||'.'||Xx.Object_Name||'@'||db_link;
     else
       stmt  := 'Create synonym '||Synown||'.'||Xx.Object_Name||' for '||Schem||'.'||Xx.Object_Name||'@'||db_link;
     end if;
    Execute Immediate stmt;
   Dbms_Output.Put_Line(stmt);

   Tot   := Tot + 1;
--
  Exception
    When AlreadyExists then
        Errs := Errs + 1;
    When Others Then
        Msg := SQLERRM(sqlcode);
        Dbms_Output.Put_Line(' Error ! :'||Msg);
  End;
 End Loop;
--Create synonym CALC02013Q4.PKG_SET_DATES_CONTEXT for EDWQ3.PKG_SET_DATES_CONTEXT@DEV_SEM_LAY
 Dbms_Output.Put_Line('> Last Statement : '||stmt);
 Dbms_Output.Put_Line('> Synonym creation failed    : '||To_Char(Errs));
 Dbms_Output.Put_Line('> Number of Synonyms existed : '||To_Char(Existingsyns));
 Dbms_Output.Put_Line('> Number of Synonyms created : '||To_Char(Tot));
 End;
/
--
spool off;
quit;
EOF
ZZ_RETVALUE=$?
echo "Value returned for Creating New Schema and Synonyms : ${ZZ_RETVALUE}" >> $LOG_OUTPUT_FILE 2>&1
if [ ${ZZ_RETVALUE} -ne 0 ]; then
  ZZ_abort
fi

echo "Script Finished : $(date)" >> $LOG_OUTPUT_FILE 2>&1
mail -s "Script ${SCRIPT_NAME} Finished: " peter.hagman@atradius.com < $LOG_OUTPUT_FILE

#
exit 0
